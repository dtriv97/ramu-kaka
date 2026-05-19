#!/usr/bin/env bash
# LiteLLM venv + config + systemd (plan.md §2.3). Run from repo checkout on the Pi.
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Run as a normal user with sudo." >&2
  exit 1
fi

if ! id -u aiagent &>/dev/null; then
  echo "User aiagent missing; run pi/scripts/phase1-security.sh first." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VENV="/home/aiagent/venvs/litellm"

sudo apt install -y python3-venv python3-pip

sudo mkdir -p /home/aiagent/venvs
sudo chown aiagent:aiagent /home/aiagent/venvs

if [[ ! -d "${VENV}" ]]; then
  sudo -u aiagent python3 -m venv "${VENV}"
fi

sudo -u aiagent "${VENV}/bin/pip" install -U pip
sudo -u aiagent "${VENV}/bin/pip" install 'litellm[proxy]'

CFG_DST=/home/aiagent/litellm_config.yaml
if [[ ! -f "${CFG_DST}" ]]; then
  sudo install -o aiagent -g aiagent -m 600 "${REPO_ROOT}/pi/config/litellm_config.yaml.example" "${CFG_DST}"
  echo "Installed ${CFG_DST} — edit master_key before starting litellm."
else
  echo "${CFG_DST} already exists; not overwriting."
fi

sudo install -m 644 "${REPO_ROOT}/pi/systemd/litellm.service" /etc/systemd/system/litellm.service
sudo systemctl daemon-reload
sudo systemctl enable litellm

echo "After setting master_key in ${CFG_DST}: sudo systemctl restart litellm"
echo "Verify with: pi/scripts/phase2-verify.sh"
