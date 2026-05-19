#!/bin/bash
# Defense-in-depth: block 169.254.169.254 at the OS level.
# Runs once on first boot via cloud-init.
# Root keeps access (you can flip this by removing the --owner clause)
# so that yc-guest-agent and cloud-init themselves still work.
set -euo pipefail

LOG=/var/log/harden-metadata.log
exec >>"$LOG" 2>&1
echo "[$(date -Is)] applying metadata block via iptables"

apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables iptables-persistent

# Drop all egress to the metadata IP from non-root users.
# Root is exempted so the guest agent / cloud-init can still read instance ID.
iptables -I OUTPUT 1 -d 169.254.169.254 -m owner ! --uid-owner 0 -j REJECT --reject-with icmp-port-unreachable

# Persist across reboots.
mkdir -p /etc/iptables
iptables-save >/etc/iptables/rules.v4
systemctl enable netfilter-persistent || true

echo "[$(date -Is)] done"
