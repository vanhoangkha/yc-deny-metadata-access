## Denying access to the VM metadata service in Yandex Cloud

#### Why this matters
Every Yandex Cloud Compute VM has access, by default, to the metadata service at
`http://169.254.169.254`. From inside the VM, any local process — including a
compromised web app or a container running as a non-privileged user — can fetch:

- the **IAM token** of the service account attached to the VM (full SA privileges);
- the VM's **user-data** (frequently used to bootstrap secrets);
- the **SSH public keys** provisioned on the VM;
- the instance identity document.

This is the cloud equivalent of [SSRF → IMDS → cloud account](https://owasp.org/www-project-web-security-testing-guide/v42/4-Web_Application_Security_Testing/07-Input_Validation_Testing/19-Testing_for_Server-Side_Request_Forgery).
The mitigation is to deny metadata access on VMs that don't actually need it,
and to scope it as narrowly as possible on VMs that do.

#### What this Terraform deploys
- :white_check_mark: A VPC network + subnet for the demo.
- :white_check_mark: A service account with `viewer` rights, attached to the VMs
  (so the "what an attacker would get" demo is real).
- :white_check_mark: A **hardened** VM, configured according to `hardening_mode`:
  - `endpoint` &mdash; sets `gce-http-endpoint=disabled`. All requests to
    `169.254.169.254` return HTTP 400.
  - `token` &mdash; sets `gce-http-token=disabled`. Only the IAM-token endpoint
    is killed; user-data / ssh-keys / instance-id remain readable.
  - `iptables` &mdash; leaves both metadata flags at their defaults but installs
    an iptables rule (via cloud-init) that drops egress to `169.254.169.254`
    for every non-root UID. Defense-in-depth for the case where you can't
    change the metadata flags (e.g. shared image baked elsewhere).
  - `all` (default) &mdash; applies the endpoint flag AND the iptables block.
- :white_check_mark: An **optional baseline** VM with no hardening, for
  side-by-side verification (`include_baseline_vm = true`, default).

#### Solution diagram
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

#### Prerequisites
- Yandex Cloud account with a folder you can write to.
- `yc` CLI configured (`yc init`).
- A service account key file for Terraform (`key.json`). See
  [docs](https://cloud.yandex.ru/docs/iam/operations/iam-token/create-for-sa).
- Terraform ≥ 1.0 and the [`yandex-cloud/yandex`](https://registry.terraform.io/providers/yandex-cloud/yandex/latest) provider.
- An SSH public key (defaults to `~/.ssh/id_rsa.pub`).

#### Deploy
```bash
terraform init
terraform apply \
  -var cloud_id=$(yc config get cloud-id) \
  -var folder_id=$(yc config get folder-id) \
  -var hardening_mode=all
```

`hardening_mode` accepts: `endpoint`, `token`, `iptables`, `all`.

#### Verify

SSH in as `yc-user` to **both** VMs and run:

```bash
# Try to grab an IAM token from metadata. On the hardened VM this must fail.
curl -sS -m 3 -H "Metadata-Flavor:Google" \
  http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token
```

Expected results:

| `hardening_mode` | What curl returns                                       |
| ---------------- | ------------------------------------------------------- |
| `token`          | `HTTP 400 BadRequest` — only the token endpoint is off  |
| `endpoint`       | `HTTP 400 BadRequest` for any path                      |
| `iptables`       | `Connection refused` from non-root, works as root       |
| `all`            | `Connection refused` from non-root; baseline path also returns `HTTP 400` |

On the **baseline** VM the same curl returns a valid IAM token JSON — that
contrast is the proof.

#### Verifying with the Yandex Cloud CLI
The CLI uses the metadata service for instance-profile auth. On the hardened
VM:
```bash
yc resource-manager folder list   # should fail to authenticate
```
On the baseline VM the same command lists the folder — because the SA token
is freely available.

#### What gets left enabled
Keeping `gce-http-token=disabled` instead of `gce-http-endpoint=disabled` is a
common compromise: tools that legitimately read user-data on boot (cloud-init
itself, image bootstrappers) keep working, while no in-VM process can mint an
IAM token. Pick the mode that matches your workload.

#### Notes for Kubernetes (Managed Service for Kubernetes)
Pods inherit the node's metadata access. A pod running as non-root cannot
read metadata if you apply the iptables rule on each node. A cleaner
alternative is a `NetworkPolicy` that denies egress to `169.254.169.254/32`
from every namespace except `kube-system`. That pattern is out of scope for
this repo — see the [Kubernetes security examples](https://github.com/yandex-cloud/yc-solution-library-for-security/tree/master/kubernetes-security)
in the parent library.

#### Cleanup
```bash
terraform destroy
```

#### Variables
| Name                  | Description                                  | Default            |
| --------------------- | -------------------------------------------- | ------------------ |
| `token`               | Path to SA key JSON                          | `key.json`         |
| `cloud_id`            | Yandex Cloud ID                              | _required_         |
| `folder_id`           | Folder ID                                    | _required_         |
| `zone`                | Availability zone                            | `ru-central1-a`    |
| `hardening_mode`      | `endpoint` / `token` / `iptables` / `all`    | `all`              |
| `vm_image_family`     | Compute image family                         | `ubuntu-2204-lts`  |
| `ssh_public_key_path` | Path to an SSH public key                    | `~/.ssh/id_rsa.pub`|
| `ssh_user`            | Username created on the VM                   | `yc-user`          |
| `include_baseline_vm` | Also deploy an unhardened VM for comparison  | `true`             |

#### References
- [VM metadata service documentation](https://yandex.cloud/en/docs/compute/concepts/vm-metadata)
- [IAM security best practices](https://yandex.cloud/en/docs/iam/best-practices/using-iam-securely)
- [Yandex Cloud Security Standard 1.1](https://yandex.cloud/docs/security/standard/all)
