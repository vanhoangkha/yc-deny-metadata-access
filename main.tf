# ---------------------------------------------------------------------
# Demo network for the hardened VM(s).
# Kept minimal — replace with your own network if you already have one
# and reference its id via data sources.
# ---------------------------------------------------------------------
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "yandex_vpc_network" "this" {
  name        = "deny-metadata-net-${random_string.suffix.result}"
  description = "Network for the deny-metadata demo"
  folder_id   = var.folder_id
}

resource "yandex_vpc_subnet" "this" {
  name           = "deny-metadata-subnet-${random_string.suffix.result}"
  zone           = var.zone
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = ["10.130.0.0/24"]
  folder_id      = var.folder_id
}

# ---------------------------------------------------------------------
# Service account attached to the hardened VM.
# Crucially: it has resource-manager viewer rights, so if the metadata
# IAM-token endpoint were left open, anyone on the VM could list the
# folder. The whole point of this solution is to deny that path.
# ---------------------------------------------------------------------
resource "yandex_iam_service_account" "vm" {
  name        = "deny-metadata-sa-${random_string.suffix.result}"
  description = "SA attached to demo VMs; intentionally has viewer rights"
  folder_id   = var.folder_id
}

resource "yandex_resourcemanager_folder_iam_member" "vm_viewer" {
  folder_id = var.folder_id
  role      = "viewer"
  member    = "serviceAccount:${yandex_iam_service_account.vm.id}"
}

# ---------------------------------------------------------------------
# Pick the latest Ubuntu image from the chosen family.
# ---------------------------------------------------------------------
data "yandex_compute_image" "ubuntu" {
  family = var.vm_image_family
}

# ---------------------------------------------------------------------
# Resolve the metadata flags from the chosen hardening_mode.
#   endpoint -> kill the whole 169.254.169.254 service
#   token    -> only kill the IAM-token endpoint (user-data still works)
#   iptables -> leave both flags enabled, rely on the OS-level block
#   all      -> both metadata flags off AND OS-level block (recommended)
# ---------------------------------------------------------------------
locals {
  disable_endpoint = var.hardening_mode == "endpoint" || var.hardening_mode == "all"
  disable_token    = var.hardening_mode == "token" || var.hardening_mode == "all" || local.disable_endpoint
  apply_iptables   = var.hardening_mode == "iptables" || var.hardening_mode == "all"

  hardened_metadata = merge(
    {
      ssh-keys  = "${var.ssh_user}:${file(var.ssh_public_key_path)}"
      user-data = local.apply_iptables ? file("${path.module}/files/harden-metadata.sh") : ""
    },
    local.disable_endpoint ? { gce-http-endpoint = "disabled" } : {},
    local.disable_token ? { gce-http-token = "disabled" } : {},
  )
}

# ---------------------------------------------------------------------
# Hardened VM — metadata is denied per `hardening_mode`.
# ---------------------------------------------------------------------
resource "yandex_compute_instance" "hardened" {
  name               = "vm-hardened-${random_string.suffix.result}"
  zone               = var.zone
  folder_id          = var.folder_id
  service_account_id = yandex_iam_service_account.vm.id
  platform_id        = "standard-v3"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.this.id
    nat       = true
  }

  metadata = local.hardened_metadata
}

# ---------------------------------------------------------------------
# (Optional) Baseline VM with the metadata service left WIDE OPEN.
# Used only for side-by-side verification — destroy it after testing.
# ---------------------------------------------------------------------
resource "yandex_compute_instance" "baseline" {
  count = var.include_baseline_vm ? 1 : 0

  name               = "vm-baseline-${random_string.suffix.result}"
  zone               = var.zone
  folder_id          = var.folder_id
  service_account_id = yandex_iam_service_account.vm.id
  platform_id        = "standard-v3"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.this.id
    nat       = true
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_public_key_path)}"
  }
}
