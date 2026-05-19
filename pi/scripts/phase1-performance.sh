#!/usr/bin/env bash
# Headless performance tweaks from plan.md §1.3 (idempotent where possible).
# Reboot required after run for config.txt changes.
#
# Optional: RAMU_DISABLE_WIFI=1 to append dtoverlay=disable-wifi (Ethernet-only setups).
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Run as a normal user with sudo (not as root)." >&2
  exit 1
fi

CONFIG=""
if [[ -f /boot/firmware/config.txt ]]; then
  CONFIG=/boot/firmware/config.txt
elif [[ -f /boot/config.txt ]]; then
  CONFIG=/boot/config.txt
else
  echo "Could not find /boot/firmware/config.txt or /boot/config.txt" >&2
  exit 1
fi

append_once() {
  local line="$1"
  if sudo grep -qxF "${line}" "${CONFIG}" 2>/dev/null; then
    echo "Already present: ${line}"
  else
    echo "${line}" | sudo tee -a "${CONFIG}" >/dev/null
    echo "Appended: ${line}"
  fi
}

append_once "gpu_mem=16"
append_once "dtoverlay=disable-bt"

if [[ "${RAMU_DISABLE_WIFI:-0}" == "1" ]]; then
  append_once "dtoverlay=disable-wifi"
else
  echo "Skipping disable-wifi (set RAMU_DISABLE_WIFI=1 if you use Ethernet only)."
fi

sudo systemctl disable hciuart.service 2>/dev/null || true
sudo systemctl disable bluetooth.service 2>/dev/null || true

for svc in avahi-daemon triggerhappy dphys-swapfile; do
  if systemctl list-unit-files "${svc}.service" &>/dev/null; then
    sudo systemctl disable "${svc}.service" 2>/dev/null || true
    echo "Disabled ${svc}.service (if it existed)."
  fi
done

sudo apt install -y cpufrequtils
echo 'GOVERNOR="performance"' | sudo tee /etc/default/cpufrequtils >/dev/null
sudo systemctl enable cpufrequtils 2>/dev/null || true

echo
echo "Reboot to apply firmware settings: sudo reboot"
echo "Then check: free -h"
