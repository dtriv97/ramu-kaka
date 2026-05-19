#!/usr/bin/env bash
# Chat completion via LiteLLM (plan.md §2.4).
set -euo pipefail

KEY="${LITELLM_MASTER_KEY:-}"
if [[ -z "${KEY}" ]]; then
  echo "Set LITELLM_MASTER_KEY to the same value as general_settings.master_key in litellm_config.yaml" >&2
  exit 1
fi

curl -sS "http://127.0.0.1:4000/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${KEY}" \
  -d '{"model": "default", "messages": [{"role": "user", "content": "Reply with OK"}]}' | head -c 800
echo
