#!/usr/bin/env bash
# Run on the Raspberry Pi after first SSH login (64-bit Pi OS Lite).
set -euo pipefail

sudo apt update
sudo apt full-upgrade -y
sudo apt autoremove -y

echo "Optional: sudo apt install unattended-upgrades && sudo dpkg-reconfigure unattended-upgrades"
