#!/usr/bin/env bash
# Cron (root recommended): */5 * * * * /path/to/pi/scripts/watchdog.sh — plan.md §9.2
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  SCTL=systemctl
else
  SCTL="sudo systemctl"
fi

for svc in ollama litellm clawdbot; do
  if systemctl list-unit-files "${svc}.service" &>/dev/null; then
    if ! systemctl is-active --quiet "${svc}.service"; then
      logger "ramu-kaka watchdog: restarting ${svc}"
      ${SCTL} restart "${svc}.service" || true
    fi
  fi
done
