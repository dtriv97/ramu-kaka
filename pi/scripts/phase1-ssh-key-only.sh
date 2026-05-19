#!/usr/bin/env bash
# Disables password authentication for SSH after you have key access working.
# ONLY run when: ssh-copy-id already succeeded and you can login without a password.
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Run as a normal user with sudo." >&2
  exit 1
fi

read -r -p "Confirm password SSH will be disabled. Continue? [y/N] " ans
[[ "${ans}" =~ ^[yY]$ ]] || exit 1

SSHCFG=/etc/ssh/sshd_config
sudo cp -a "${SSHCFG}" "${SSHCFG}.bak.$(date +%s)"

sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "${SSHCFG}"
sudo sed -i 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' "${SSHCFG}" || true

if sudo sshd -t; then
  sudo systemctl restart ssh || sudo systemctl restart sshd
  echo "Password SSH disabled. Keep this session open until you verify a new SSH connection with keys."
else
  echo "sshd -t failed; restoring backup." >&2
  sudo cp "${SSHCFG}.bak."* "${SSHCFG}" 2>/dev/null || true
  exit 1
fi
