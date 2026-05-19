variable "token" {
  description = "Path to Yandex Cloud service account key JSON file"
  type        = string
  default     = "key.json" # https://cloud.yandex.ru/docs/iam/operations/iam-token/create-for-sa
}

variable "cloud_id" {
  description = "Yandex Cloud ID where resources will be created"
  type        = string
  # yc config get cloud-id
}

variable "folder_id" {
  description = "Yandex Cloud Folder ID where resources will be created"
  type        = string
  # yc config get folder-id
}

variable "zone" {
  description = "Yandex Cloud availability zone"
  type        = string
  default     = "ru-central1-a"
}

# ---------------------------------------------------------------------
# Metadata hardening mode for the demo VM.
#   - "endpoint": fully disable the metadata endpoint (gce-http-endpoint=disabled).
#                Any GET to 169.254.169.254 returns HTTP 400.
#   - "token":   only disable IAM-token issuance (gce-http-token=disabled).
#                user-data / ssh-keys / instance-id remain readable.
#   - "iptables": leave metadata flags at defaults, but block 169.254.169.254
#                 at the OS level for all non-root users via iptables --owner.
#   - "all":      apply both gce-http-endpoint=disabled AND iptables block.
# ---------------------------------------------------------------------
variable "hardening_mode" {
  description = "How to deny metadata access on the demo VM"
  type        = string
  default     = "all"

  validation {
    condition     = contains(["endpoint", "token", "iptables", "all"], var.hardening_mode)
    error_message = "hardening_mode must be one of: endpoint, token, iptables, all."
  }
}

variable "vm_image_family" {
  description = "Compute image family for the demo VM"
  type        = string
  default     = "ubuntu-2204-lts"
}

variable "ssh_public_key_path" {
  description = "Path to an SSH public key that will be added to the demo VM"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_user" {
  description = "Username created on the VM that owns the SSH key above"
  type        = string
  default     = "yc-user"
}

variable "include_baseline_vm" {
  description = "Also deploy a 'baseline' VM with default metadata settings, for comparison"
  type        = bool
  default     = true
}
