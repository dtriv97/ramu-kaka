# Ramu Kaka — Raspberry Pi deployment

This folder automates [plan.md](../plan.md) on a **Raspberry Pi** (tested target: Pi 4B 4GB, Pi OS Lite **64-bit**). Flash the SD card and complete first boot **before** running these scripts.

## 1. Hardware and imaging (manual)

1. Assemble Pi, PSU, cooling, Ethernet (preferred).
2. **Raspberry Pi Imager** → **Raspberry Pi OS Lite (64-bit)**.
3. Imager advanced: **SSH**, user/password, Wi‑Fi if needed.
4. Boot, find IP, `ssh youruser@<ip>`.
5. (Recommended) Router **DHCP reservation** for a stable LAN IP.

## 2. Phase 1 — updates, performance, security

From a copy of this repo on the Pi (or clone it):

```bash
chmod +x pi/scripts/*.sh

./pi/scripts/phase1-update.sh
./pi/scripts/phase1-performance.sh
# Ethernet-only: RAMU_DISABLE_WIFI=1 ./pi/scripts/phase1-performance.sh
sudo reboot
```

After reboot:

```bash
free -h
./pi/scripts/phase1-security.sh
```

On your **PC**, install your SSH key, then on the Pi (only when key login works):

```bash
./pi/scripts/phase1-ssh-key-only.sh
```

Optional unattended upgrades (see plan §1.2):

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure unattended-upgrades
```

## 3. Phase 2 — Ollama + LiteLLM (before Clawdbot)

Default pulls **gemma2:2b** and **tinyllama**. Skip pulls with `RAMU_PULL_MODELS=0 ./pi/scripts/phase2-ollama.sh`.

```bash
./pi/scripts/phase2-ollama.sh
./pi/scripts/phase2-litellm.sh
nano /home/aiagent/litellm_config.yaml   # set master_key
sudo systemctl restart litellm
export LITELLM_MASTER_KEY='your-master-key'
./pi/scripts/phase2-verify.sh
```

## 4. Phase 3 — Clawdbot + Telegram

Install Node and Clawdbot (installs to your **current** user). For systemd as **aiagent**, run onboarding as that user:

```bash
sudo apt install -y sudo
sudo loginctl enable-linger aiagent   # optional: user services / login
sudo su - aiagent
./pi/scripts/phase3-node-clawdbot.sh
clawdbot onboard
```

Use in the wizard (plan §3.2):

- LLM: OpenAI-compatible base URL `http://127.0.0.1:4000`
- Model: `default`
- API key: same as LiteLLM `master_key`

Telegram (plan §4): `@BotFather` token, `@userinfobot` for your numeric ID, **allowlist only yourself**.

Install the unit (edit paths if `which clawdbot` differs):

```bash
sudo cp pi/systemd/clawdbot.service.example /etc/systemd/system/clawdbot.service
sudo systemctl daemon-reload
sudo systemctl enable --now clawdbot
journalctl -u clawdbot -f
```

See [env.telegram.example](env.telegram.example) for variable names many setups use.

## 5. Phase 5+ — Tailscale, skills, monitoring

**Tailscale** (private SSH from anywhere):

```bash
./pi/scripts/phase5-tailscale.sh
sudo tailscale up
```

**Optional watchdog** (root cron):

```bash
sudo crontab -e
# */5 * * * * /home/aiagent/ramu-kaka/pi/scripts/watchdog.sh
```

**Skills** (plan §7) after Clawdbot works:

```bash
./pi/scripts/phase7-skills.sh
```

**Pi-hole** (§6), **persona/memory** (§8–9), strict outbound **ufw**: follow [plan.md](../plan.md).

## Files

| Path | Role |
|------|------|
| [scripts/phase1-*.sh](scripts/) | OS update, performance, firewall, SSH hardening |
| [scripts/phase2-*.sh](scripts/) | Ollama, LiteLLM venv + systemd, stack verify |
| [scripts/phase3-node-clawdbot.sh](scripts/phase3-node-clawdbot.sh) | Node 22 + Clawdbot install |
| [scripts/phase5-tailscale.sh](scripts/phase5-tailscale.sh) | Tailscale installer |
| [scripts/watchdog.sh](scripts/watchdog.sh) | Restart dead units |
| [config/litellm_config.yaml.example](config/litellm_config.yaml.example) | LiteLLM router template |
| [systemd/litellm.service](systemd/litellm.service) | LiteLLM unit |
| [systemd/clawdbot.service.example](systemd/clawdbot.service.example) | Agent unit template |
