## Запрет доступа к сервису метаданных ВМ в Yandex Cloud

#### Зачем это нужно
По умолчанию любая ВМ Yandex Compute Cloud имеет доступ к сервису метаданных
по адресу `http://169.254.169.254`. Из ВМ любой локальный процесс — включая
скомпрометированное веб-приложение или контейнер, запущенный от непривилегированного
пользователя — может получить:

- **IAM-токен** сервисного аккаунта, привязанного к ВМ (все его права);
- **user-data** ВМ (часто используется для начальной загрузки секретов);
- **SSH-ключи**, выданные ВМ;
- идентификационный документ инстанса.

Это облачный аналог цепочки [SSRF → IMDS → cloud account](https://owasp.org/www-project-web-security-testing-guide/v42/4-Web_Application_Security_Testing/07-Input_Validation_Testing/19-Testing_for_Server-Side_Request_Forgery).
Минимизация — запретить доступ к метаданным на ВМ, которым это не нужно, и
максимально сузить доступ там, где он необходим.

#### Что разворачивает Terraform
- :white_check_mark: VPC-сеть и подсеть для демонстрации.
- :white_check_mark: Сервисный аккаунт с ролью `viewer`, привязанный к ВМ —
  чтобы демонстрация «что увидит атакующий» была настоящей.
- :white_check_mark: **Hardened** ВМ, поведение задаётся переменной `hardening_mode`:
  - `endpoint` — устанавливает `gce-http-endpoint=disabled`. Все запросы к
    `169.254.169.254` возвращают HTTP 400.
  - `token` — устанавливает `gce-http-token=disabled`. Отключается только
    endpoint выдачи IAM-токенов; user-data / ssh-keys / instance-id остаются
    доступными.
  - `iptables` — оба флага метаданных оставлены по умолчанию, но через
    cloud-init добавляется правило iptables, блокирующее исходящий трафик к
    `169.254.169.254` для всех UID, кроме root. Подходит, если флаги
    метаданных менять нельзя (например, образ собирается в другом месте).
  - `all` (по умолчанию) — применяются и флаг endpoint, и iptables-блок.
- :white_check_mark: **Опциональная baseline-ВМ** без харденинга для
  сравнения (`include_baseline_vm = true`, по умолчанию).

#### Схема решения
```
                +---------------------------+
                |  Yandex Cloud Folder      |
                |                           |
   client --->  |  +---------------------+  |
                |  | vm-hardened          |  |
                |  | gce-http-endpoint=   |  |
                |  |   disabled           |  |
                |  | iptables OUTPUT drop |--|--X--> 169.254.169.254 (blocked)
                |  +---------------------+  |
                |                           |
                |  +---------------------+  |
                |  | vm-baseline          |  |
                |  | (defaults)           |--|----> 169.254.169.254 (open!)
                |  +---------------------+  |
                +---------------------------+
```

#### Предварительные требования
- Аккаунт Yandex Cloud и фолдер с правами на запись.
- Настроенный CLI `yc` (`yc init`).
- Файл ключа сервисного аккаунта для Terraform (`key.json`). См.
  [документацию](https://cloud.yandex.ru/docs/iam/operations/iam-token/create-for-sa).
- Terraform ≥ 1.0 и провайдер [`yandex-cloud/yandex`](https://registry.terraform.io/providers/yandex-cloud/yandex/latest).
- SSH-публичный ключ (по умолчанию `~/.ssh/id_rsa.pub`).

#### Развёртывание
```bash
terraform init
terraform apply \
  -var cloud_id=$(yc config get cloud-id) \
  -var folder_id=$(yc config get folder-id) \
  -var hardening_mode=all
```

Допустимые значения `hardening_mode`: `endpoint`, `token`, `iptables`, `all`.

#### Проверка

Подключитесь по SSH под пользователем `yc-user` к **обеим** ВМ и выполните:

```bash
# Попытка получить IAM-токен из метаданных. На hardened ВМ должно упасть.
curl -sS -m 3 -H "Metadata-Flavor:Google" \
  http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token
```

Ожидаемое поведение:

| `hardening_mode` | Результат curl                                            |
| ---------------- | --------------------------------------------------------- |
| `token`          | `HTTP 400 BadRequest` — отключён только endpoint токена   |
| `endpoint`       | `HTTP 400 BadRequest` на любой путь                       |
| `iptables`       | `Connection refused` от не-root; от root работает         |
| `all`            | `Connection refused` от не-root; baseline-путь — `HTTP 400` |

На **baseline**-ВМ тот же curl вернёт валидный JSON с IAM-токеном — это и есть
доказательство, что харденинг работает.

#### Проверка через Yandex Cloud CLI
CLI использует metadata-сервис для аутентификации через профиль инстанса. На
hardened ВМ:
```bash
yc resource-manager folder list   # не сможет аутентифицироваться
```
На baseline-ВМ та же команда вернёт список фолдеров — токен СА доступен.

#### Что остаётся включённым
Сохранить `gce-http-token=disabled` вместо `gce-http-endpoint=disabled` — типичный
компромисс: инструменты, которым нужен user-data при загрузке (сам cloud-init,
скрипты bootstrap образа), продолжают работать, но никакой процесс внутри ВМ не
сможет получить IAM-токен. Выбирайте режим под свою нагрузку.

#### Замечание для Managed Service for Kubernetes
Поды наследуют доступ к метаданным от узла. Под, запущенный не от root, не
сможет читать метаданные, если на каждом узле включено iptables-правило.
Более чистое решение — `NetworkPolicy`, запрещающий egress к
`169.254.169.254/32` из всех неймспейсов, кроме `kube-system`. Этот сценарий
вне зоны данного репозитория — см. примеры
[Kubernetes security](https://github.com/yandex-cloud/yc-solution-library-for-security/tree/master/kubernetes-security)
в родительской библиотеке.

#### Очистка
```bash
terraform destroy
```

#### Переменные
| Имя                   | Описание                                       | По умолчанию       |
| --------------------- | ---------------------------------------------- | ------------------ |
| `token`               | Путь к файлу ключа СА                          | `key.json`         |
| `cloud_id`            | Yandex Cloud ID                                | _обязательная_     |
| `folder_id`           | Folder ID                                      | _обязательная_     |
| `zone`                | Зона доступности                               | `ru-central1-a`    |
| `hardening_mode`      | `endpoint` / `token` / `iptables` / `all`      | `all`              |
| `vm_image_family`     | Семейство образов Compute                      | `ubuntu-2204-lts`  |
| `ssh_public_key_path` | Путь к публичному SSH-ключу                    | `~/.ssh/id_rsa.pub`|
| `ssh_user`            | Имя пользователя на ВМ                         | `yc-user`          |
| `include_baseline_vm` | Развёртывать незахардененную ВМ для сравнения  | `true`             |

#### Ссылки
- [Документация сервиса метаданных ВМ](https://yandex.cloud/ru/docs/compute/concepts/vm-metadata)
- [Best practices по безопасности IAM](https://yandex.cloud/ru/docs/iam/best-practices/using-iam-securely)
- [Yandex Cloud Security Standard 1.1](https://yandex.cloud/docs/security/standard/all)
