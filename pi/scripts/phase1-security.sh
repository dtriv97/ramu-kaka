#!/usr/bin/env bash
# Firewall, fail2ban, and aiagent user (plan.md §1.5). Does NOT disable SSH passwords.
# Run ssh-copy-id first; then optionally: ./phase1-ssh-key-only.sh
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Run as a normal user with sudo (not as root)." >&2
  exit 1
fi

sudo apt install -y ufw fail2ban

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw --force enable

if id -u aiagent &>/dev/null; then
  echo "User aiagent already exists."
else
  sudo useradd -m -s /bin/bash aiagent
  sudo usermod -aG sudo aiagent
  echo "Created user aiagent (set a password if needed: sudo passwd aiagent)."
fi

echo "UFW enabled. fail2ban installed. Next: copy repo to Pi or clone, then phase2 scripts as aiagent where noted."
