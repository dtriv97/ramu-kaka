#!/usr/bin/env bash
# Node.js 22 + Clawdbot installer (plan.md §3.2). Interactive onboard is manual.
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Run as a normal user with sudo." >&2
  exit 1
fi

curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs

echo "Node: $(node -v)"

curl -fsSL https://openclaw.ai/install.sh | bash

echo
echo "Next (manual): run 'clawdbot onboard' as the user that will run the agent."
echo "  - Channel: Telegram"
echo "  - LLM: Custom / OpenAI-compatible"
echo "  - Base URL: http://127.0.0.1:4000"
echo "  - Model: default"
echo "  - API key: same as LiteLLM master_key"
echo
echo "Then install systemd unit (adjust paths if needed):"
echo "  sudo cp $(dirname "$0")/../systemd/clawdbot.service.example /etc/systemd/system/clawdbot.service"
echo "  sudo systemctl daemon-reload && sudo systemctl enable --now clawdbot"
