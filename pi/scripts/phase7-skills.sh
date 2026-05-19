#!/usr/bin/env bash
# Install common Clawhub skills (plan.md §7.1). Run as the Clawdbot user after onboard.
set -euo pipefail

SKILLS=(
  browser-automation
  web-search
  news-monitor
  price-tracker
  code-runner
  scheduler
  file-manager
  rss-reader
)

for s in "${SKILLS[@]}"; do
  echo "=== Installing ${s} ==="
  npx -y clawhub@latest install "${s}"
done

echo "Optional: npx -y clawhub@latest install memory-vector"
