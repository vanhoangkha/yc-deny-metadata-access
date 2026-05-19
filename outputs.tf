output "hardened_vm_external_ip" {
  description = "Public IP of the hardened VM. SSH in and try to reach 169.254.169.254."
  value       = yandex_compute_instance.hardened.network_interface[0].nat_ip_address
}

output "baseline_vm_external_ip" {
  description = "Public IP of the baseline (insecure) VM, if it was deployed."
  value       = try(yandex_compute_instance.baseline[0].network_interface[0].nat_ip_address, null)
}

output "hardening_mode" {
  description = "Mode applied to the hardened VM"
  value       = var.hardening_mode
}

output "verification_commands" {
  description = "Run these on the hardened VM to confirm metadata is blocked"
  value = <<-EOT
    # 1) Endpoint reachability — expect connection refused / 400 / timeout depending on mode:
    curl -sS -m 3 -H "Metadata-Flavor:Google" \
      http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token

    # 2) Yandex-style IAM token path — same expectation:
    curl -sS -m 3 -H "Metadata-Flavor:Google" \
      http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token

    # 3) yc CLI from a non-root user — should fail to authenticate via metadata:
    yc --no-user-output config profile activate metadata-instance || true
    yc resource-manager folder list

    # 4) On the BASELINE VM the same commands succeed — that contrast is the test.
  EOT
}
