#!/usr/bin/env bash
# Tailscale install (plan.md §5.2). Auth is interactive: sudo tailscale up
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Run as a normal user with sudo." >&2
  exit 1
fi

curl -fsSL https://tailscale.com/install.sh | sh
echo "Run: sudo tailscale up"
echo "Then SSH: ssh aiagent@<tailscale-ip>"
