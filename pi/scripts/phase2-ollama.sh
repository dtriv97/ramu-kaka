#!/usr/bin/env bash
# Install Ollama and Pi 4B 4GB limits (plan.md §2.1).
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Run as a normal user with sudo." >&2
  exit 1
fi

curl -fsSL https://ollama.com/install.sh | sh

sudo systemctl enable ollama
sudo systemctl start ollama

sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo tee /etc/systemd/system/ollama.service.d/limits.conf >/dev/null <<'EOF'
[Service]
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_CONTEXT_LENGTH=2048"
EOF

sudo systemctl daemon-reload
sudo systemctl restart ollama

if [[ "${RAMU_PULL_MODELS:-1}" == "1" ]]; then
  ollama pull gemma2:2b
  ollama pull tinyllama
  ollama list
fi

echo "Quick test: ollama run gemma2:2b \"Say hello in one sentence.\""
