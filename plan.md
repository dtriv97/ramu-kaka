# Personal AI Agent on Raspberry Pi — Master Plan

## Problem Statement
Build a self-hosted, always-on personal AI agent on a Raspberry Pi using Clawdbot/OpenClaw.
The agent must be remotely controllable (via messaging), able to access the internet in a controlled
way, and act as a human-like assistant (research, deals, news, utility apps).

**Core constraints:**
- **Local LLM from day one** — Ollama is the primary brain of the agent, set up before Clawdbot
- **Zero paid AI APIs, ever** — only free-tier cloud APIs (e.g. Gemini free) as an optional fallback
- **Model flexibility** — architecture must allow easy model switching, testing, and future automation of model management

---

## Architecture Overview

```
[You — Phone/PC]
       │
       │  Telegram messaging
       ▼
[Telegram Bot API]  ◄──────────────────────────────────────────────────────────┐
       │                                                                         │
       ▼                                                                         │
[Clawdbot / OpenClaw Agent]  ── on ──►  [Raspberry Pi 5 — 8GB RAM]            │
       │                                         │                               │
       ├── [LiteLLM Proxy]  ──────────────►  [Ollama]                          │
       │      (model router)                     │                               │
       │      routes by task type                ├── gemma2:2b  (fast/general)  │
       │                                         ├── qwen2.5:3b (reasoning)     │
       │                                         ├── phi3:mini  (light tasks)   │
       │                                         └── [future models...]         │
       │                                                                         │
       ├── [Skills / Plugins]               Tailscale (secure SSH/admin)        │
       │     • browser-automation (Playwright)                                   │
       │     • web search / scraping             │                               │
       │     • scheduler / cron jobs             │                               │
       │     • code execution sandbox            │                               │
       │     • rss-reader / news monitor         │                               │
       │     • file manager                      │                               │
       │                                         │                               │
       └── [Free-tier Cloud API — last resort]   │                               │
             (Gemini free only, if local fails)  │                               │
                                                 │                               │
             [Cloudflare Tunnel / Tailscale] ────┘                               │
                    (remote access, no port forwarding)                          │
                                                                                 │
[Your agent sends results / reports back via Telegram] ────────────────────────┘
```

---

## Phase 1 — Hardware Setup & OS Hardening

### 1.1 Current Hardware
| Component | What You Have | Notes |
|---|---|---|
| **SBC** | Raspberry Pi 4B — 4GB RAM | Sufficient with headless OS + optimisations |
| **Storage** | 32GB SD Card or 32GB USB drive | Use USB drive if possible — better write endurance than SD |
| **Power Supply** | Official Pi 4 PSU (USB-C, 5V/3A) | Use official or quality third-party — avoid under-voltage |
| **Cooling** | Heatsink + small fan recommended | CPU runs hot under LLM inference — active cooling helps |
| **Network** | Ethernet (preferred) + WiFi backup | Ethernet = better uptime for always-on agents |
| **Access** | SSH only — fully headless | No monitor, no keyboard, no desktop ever needed |

### 1.2 OS Setup — Headless Pi OS Lite (64-bit)
> **Critical**: Always use the 64-bit Lite image. The 32-bit image cannot address full RAM and cuts your usable memory almost in half.

1. Flash **Raspberry Pi OS Lite (64-bit)** using Raspberry Pi Imager
   - In Imager: click ⚙️ Settings → enable SSH, set username/password, configure WiFi if needed
   - This means you never need a monitor attached — boot straight to SSH-ready
2. Find the Pi's IP: check your router's DHCP table, or use `nmap -sn 192.168.1.0/24`
3. SSH in: `ssh pi@<ip-address>`
4. Update fully:
   ```bash
   sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y
   ```
5. Set a static local IP (DHCP reservation on your router is easiest)
6. Set up automatic unattended security upgrades:
   ```bash
   sudo apt install unattended-upgrades
   sudo dpkg-reconfigure unattended-upgrades
   ```

### 1.3 Headless Performance Optimisations
Apply all of these — they free ~700MB of RAM and reduce CPU noise:

```bash
# --- GPU memory: set to minimum (no display = no GPU needed) ---
echo "gpu_mem=16" | sudo tee -a /boot/firmware/config.txt

# --- Disable Bluetooth (not needed, saves ~15MB + CPU) ---
echo "dtoverlay=disable-bt" | sudo tee -a /boot/firmware/config.txt
sudo systemctl disable hciuart bluetooth

# --- Disable WiFi if using Ethernet ---
# (comment this out if you need WiFi)
echo "dtoverlay=disable-wifi" | sudo tee -a /boot/firmware/config.txt

# --- Disable unnecessary background services ---
sudo systemctl disable avahi-daemon   # mDNS — not needed
sudo systemctl disable triggerhappy   # keyboard shortcuts — irrelevant
sudo systemctl disable dphys-swapfile # we manage swap manually

# --- CPU governor: full speed during inference ---
sudo apt install -y cpufrequtils
echo 'GOVERNOR="performance"' | sudo tee /etc/default/cpufrequtils

# --- Reboot to apply ---
sudo reboot
```

**After reboot, verify RAM headroom:**
```bash
free -h
# You should see ~3.7GB total available with ~3.3-3.5GB free at idle
```

### 1.4 Storage — SD Card vs USB Drive

| | SD Card (32GB) | USB Drive (32GB) |
|---|---|---|
| **Model files** | ✅ Works | ✅ Works (preferred) |
| **Write endurance** | ⚠️ Wears out faster | ✅ Better |
| **Speed** | ~20-40 MB/s read | ~25-60 MB/s read (USB 2.0 port on Pi 4B) |
| **Swap** | ❌ Avoid — kills SD cards | ⚠️ Acceptable if needed |
| **Recommendation** | Boot OS from here | Store Ollama models here |

> **Pi 4B note**: The Pi 4B has two USB 3.0 ports (blue). Plug your USB drive into one of those — not the black USB 2.0 ports — for best transfer speed.

If using a USB drive for model storage:
```bash
# Mount USB drive and redirect Ollama models to it
sudo mkdir -p /mnt/usb/ollama-models
# Add to /etc/fstab for auto-mount (replace UUID with your drive's UUID from `blkid`)
echo 'UUID=xxxx-xxxx  /mnt/usb  vfat  defaults,nofail  0  2' | sudo tee -a /etc/fstab
sudo mount -a

# Tell Ollama to store models on USB
echo 'OLLAMA_MODELS=/mnt/usb/ollama-models' | sudo tee -a /etc/environment
```

### 1.5 Security Hardening
```bash
# SSH key-only auth — generate key on your PC first, then:
ssh-copy-id pi@<pi-ip>

# Disable password SSH login
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh

# Firewall
sudo apt install -y ufw fail2ban
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw enable

# Dedicated non-root user for the agent
sudo useradd -m -s /bin/bash aiagent
sudo usermod -aG sudo aiagent
```

---

## Phase 2 — Local LLM Stack (Ollama + LiteLLM Proxy)

> **This is the brain of the agent. Set this up BEFORE Clawdbot.**

### 2.1 Install Ollama
```bash
curl -fsSL https://ollama.com/install.sh | sh
sudo systemctl enable ollama
sudo systemctl start ollama
```

**Immediately configure Ollama memory limits for Pi 4B 4GB:**
```bash
# Cap to 1 model in memory, 1 parallel request, smaller context window
sudo mkdir -p /etc/systemd/system/ollama.service.d
cat <<EOF | sudo tee /etc/systemd/system/ollama.service.d/limits.conf
[Service]
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_CONTEXT_LENGTH=2048"
EOF
sudo systemctl daemon-reload && sudo systemctl restart ollama
```

### 2.2 Recommended Models for Pi 4B 4GB (Headless, Optimised)

With the headless + optimisation setup from Phase 1, your RAM budget is:

| Component | RAM |
|---|---|
| Pi OS Lite (headless, trimmed) | ~150MB |
| Ollama daemon | ~80MB |
| LiteLLM proxy | ~130MB |
| Clawdbot (Node.js) | ~250MB |
| **Available for model** | **~3.39GB** |

| Model | File Size | RAM Usage | Speed on Pi 4B | Best For |
|---|---|---|---|---|
| **Gemma 2 (2B) Q4** | ~1.5GB | ~2.8GB | 2-4 tok/s | General tasks — **primary default** ✅ fits! |
| **Phi-3 Mini Q4** | ~2.2GB | ~2.2GB | 3-5 tok/s | Instruction following, structured tasks ✅ fits! |
| **TinyLlama (1.1B) Q4** | ~0.6GB | ~1.5GB | 5-8 tok/s | Ultra-fast fallback; use when Pi is under load ✅ |
| ~~Qwen2.5 (3B)~~ | ~2.5GB | ~5GB | — | ❌ Exceeds RAM — defer to Pi 5 upgrade |
| ~~Mistral 7B~~ | ~4.1GB | ~7GB | — | ❌ Not viable on 4GB — defer to Pi 5 upgrade |

> **Start with just Gemma2 2B + TinyLlama.** That's ~2.1GB on disk, well within your 32GB storage.

```bash
# Pull your two starting models only
ollama pull gemma2:2b
ollama pull tinyllama

# Verify
ollama list

# Quick test
ollama run gemma2:2b "Explain what you can help me with as a personal assistant"
```

### 2.3 LiteLLM Proxy — Model Router (Key for Future Flexibility)

**LiteLLM** sits between Clawdbot and Ollama as a proxy with an OpenAI-compatible API.
This means:
- Clawdbot only ever talks to one endpoint (`http://localhost:4000`)
- You swap, add, or test models without touching Clawdbot's config
- You can define routing rules (e.g., "coding tasks → qwen2.5, quick tasks → gemma2")
- If you ever add a free cloud model later, LiteLLM handles it transparently

```bash
pip install litellm[proxy]
```

**`litellm_config.yaml`** (save to `/home/aiagent/litellm_config.yaml`):
```yaml
model_list:
  - model_name: default        # Clawdbot calls this — general tasks
    litellm_params:
      model: ollama/gemma2:2b
      api_base: http://localhost:11434

  - model_name: fast           # Quick/light tasks, fallback under load
    litellm_params:
      model: ollama/tinyllama
      api_base: http://localhost:11434

  # Future models go here when you upgrade hardware:
  # - model_name: reasoning
  #   litellm_params:
  #     model: ollama/qwen2.5:3b
  #     api_base: http://localhost:11434

router_settings:
  routing_strategy: simple-shuffle

general_settings:
  master_key: "your-secret-key"     # Protect the proxy endpoint
```

```bash
# Run the proxy
litellm --config /home/aiagent/litellm_config.yaml --port 4000
```

**LiteLLM as a systemd service:**
```ini
# /etc/systemd/system/litellm.service
[Unit]
Description=LiteLLM Model Proxy
After=ollama.service

[Service]
User=aiagent
ExecStart=litellm --config /home/aiagent/litellm_config.yaml --port 4000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```
```bash
sudo systemctl enable litellm && sudo systemctl start litellm
```

### 2.4 Verify the Full Local LLM Stack
```bash
# Test that LiteLLM is routing correctly to Ollama
curl http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-secret-key" \
  -d '{"model": "default", "messages": [{"role": "user", "content": "Hello!"}]}'
```
If you get a response — the local LLM stack is working. **Proceed to Clawdbot installation.**

---

## Phase 3 — Clawdbot / OpenClaw Installation

### 3.1 What Is Clawdbot/OpenClaw?
Clawdbot (also known as **OpenClaw**) is an open-source, privacy-first personal AI agent framework designed for self-hosted deployment. It supports:
- **Multi-channel messaging** — Telegram, Discord, WhatsApp, Signal, Slack
- **Skills/Plugin system** — Markdown-driven "SKILL.md" files defining agent behaviors
- **Tool calling** — browser automation, web search, code execution, file ops, schedulers
- **Model flexibility** — pluggable LLM backend; we point it at our **LiteLLM proxy** (local Ollama)
- **Persistent memory** — remembers context, past tasks, preferences across sessions

### 3.2 Installation Steps

```bash
# Install Node.js 22+ (required)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs

# Install Clawdbot via official installer
curl -fsSL https://openclaw.ai/install.sh | bash

# Run the onboarding wizard
clawdbot onboard
# This wizard guides you through:
# - Choosing your messaging channel (Telegram recommended)
# - Selecting your LLM backend → choose "Custom / OpenAI-compatible"
# - Enter base URL: http://localhost:4000  (your LiteLLM proxy)
# - Enter model: default  (as named in litellm_config.yaml)
# - Configuring a system prompt / persona
# - Setting up the agent as a systemd service for auto-start
```

**Docker alternative (recommended for isolation):**
```bash
docker run -d \
  --name clawdbot \
  --restart unless-stopped \
  --network host \
  -v ~/clawdbot-data:/data \
  -e TELEGRAM_TOKEN=your_token \
  -e OPENAI_BASE_URL=http://localhost:4000 \
  -e OPENAI_API_KEY=your-litellm-secret-key \
  -e OPENAI_MODEL=default \
  ghcr.io/clapps/clawdbot:latest
```
> `--network host` is important so the container can reach LiteLLM on localhost.

### 3.3 Run as systemd Service (Always-On)
```ini
# /etc/systemd/system/clawdbot.service
[Unit]
Description=Clawdbot AI Agent
After=litellm.service

[Service]
User=aiagent
WorkingDirectory=/home/aiagent/clawdbot
ExecStart=/usr/bin/clawdbot start
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable clawdbot
sudo systemctl start clawdbot
```

---

## Phase 4 — Remote Messaging Interface (Telegram)

### 4.1 Why Telegram?
- **Best free option** — official Bot API, no server needed on your end
- **Multi-device** — message from phone, laptop, web
- **Rich features** — file uploads, voice messages, inline keyboards, commands
- **Supported natively** by Clawdbot/OpenClaw out of the box

### 4.2 Telegram Bot Setup
1. Open Telegram → message `@BotFather`
2. Create a new bot with `/newbot`, get the **Bot Token**
3. Get your **personal Telegram User ID** via `@userinfobot`
4. Configure Clawdbot with:
   ```
   TELEGRAM_BOT_TOKEN=your_token
   TELEGRAM_ALLOWED_USERS=your_user_id  # Restrict to only YOU
   ```
5. Send `/start` to your bot — your Pi agent is now reachable from anywhere

### 4.3 Allowlist-Only Security
**Critical**: Always restrict the bot to your Telegram user ID. This prevents anyone who finds your bot username from issuing commands to your Pi.

### 4.4 Alternative Messaging Options
| Method | Pros | Cons |
|---|---|---|
| **Telegram** ✅ | Simple, free, no port forwarding, rich API | Telegram servers see message metadata |
| **Signal** | End-to-end encrypted | More complex setup (signal-cli) |
| **Discord** | Rich embeds, familiar | Overkill for personal use |
| **Matrix/Element** | Self-hosted, fully private | Requires running your own Matrix server |
| **SSH direct** | Zero dependency | Not mobile-friendly |

**Recommendation**: Start with Telegram. It's the most battle-tested path with Clawdbot.

---

## Phase 5 — Secure Remote Access

### 5.1 The Right Tool for Each Need

| Tool | Best For | Privacy | Complexity |
|---|---|---|---|
| **Tailscale** (recommended) | SSH access, managing the Pi from laptop/PC | ★★★★★ | Very low |
| **Cloudflare Tunnel** | Exposing a web dashboard publicly with auth | ★★★★ (CF sees traffic) | Low |
| **Hybrid (both)** | Private management + optional public web UI | Best of both | Low |

### 5.2 Tailscale Setup (Private VPN Mesh)
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
# Follow the auth link in the terminal — sign in with Google/GitHub
# Your Pi now has a private Tailscale IP (e.g. 100.x.x.x)
# SSH from anywhere: ssh aiagent@100.x.x.x
```
- No port forwarding required
- Works behind CGNAT/restrictive ISPs
- Free for personal use (up to 3 users, 100 devices)

### 5.3 Cloudflare Tunnel Setup (Optional — for Web UI)
```bash
# Install cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 -o cloudflared
chmod +x cloudflared && sudo mv cloudflared /usr/local/bin/

# Authenticate and create tunnel
cloudflared tunnel login
cloudflared tunnel create pi-agent
cloudflared tunnel route dns pi-agent agent.yourdomain.com
```
Use this only if you want a web dashboard (e.g., agent logs, status page) accessible from a browser with Cloudflare Access authentication (free).

---

## Phase 6 — Internet Access (Controlled)

### 6.1 Controlled Internet Access Strategy
"Controlled" means the agent can browse the web but within defined guardrails:

**Approach 1 — Skill Permissions (built into OpenClaw)**
- Only enable the `web-search` and `browser-automation` skills — don't enable file-system or shell execution unless needed
- Skills define exactly what tools the agent can use; disable risky ones

**Approach 2 — DNS-level Filtering (Pi-hole)**
```bash
# Install Pi-hole on the same Pi (lightweight)
curl -sSL https://install.pi-hole.net | bash
```
- Block telemetry, ads, and suspicious domains at the DNS level
- Allowlist only the domains the agent needs (search engines, news sites, shopping APIs)

**Approach 3 — Outbound Firewall Rules**
```bash
# Allow only specific outbound ports
sudo ufw allow out 443/tcp  # HTTPS
sudo ufw allow out 53/udp   # DNS
sudo ufw deny out to any    # Block everything else
```

**Approach 4 — Browser Sandboxing**
- Run Playwright (browser automation) inside a Docker container with no persistent storage
- Use `--no-sandbox` only for controlled scripts; review results before acting

### 6.2 Search & Data Sources for the Agent
Configure these free APIs/tools for the agent's research skills:
- **Brave Search API** — free tier (2,000 queries/month), privacy-respecting, no paid plan needed
- **SearXNG** — self-hosted meta-search engine; aggregates Google/Bing/DuckDuckGo results with zero API cost
- **Firecrawl** — structured web scraping + crawling (has a generous free tier)
- **NewsAPI.org** — aggregated news with keyword/topic filters (free tier: 100 req/day)
- **RSS feeds** — zero-cost, reliable news and blog monitoring (the simplest option)

---

## Phase 7 — Agent Skills & Use Cases

### 7.1 Core Skills to Install
```bash
# Install via ClawHub skill manager
npx clawhub@latest install browser-automation
npx clawhub@latest install web-search
npx clawhub@latest install news-monitor
npx clawhub@latest install price-tracker
npx clawhub@latest install code-runner
npx clawhub@latest install scheduler
npx clawhub@latest install file-manager
npx clawhub@latest install rss-reader
```

### 7.2 Detailed Use Case Breakdown

#### 🔍 Research Assistant
- "Research the best noise-cancelling headphones under £150 and give me a ranked comparison"
- Agent: uses `browser-automation` → visits review sites → synthesizes findings → returns structured report via Telegram
- Skill: `web-search` + `browser-automation` + `report-writer`

#### 💰 Deal Finder & Price Tracker
- "Track the price of [product] on Amazon and alert me when it drops below £X"
- Agent: uses `price-tracker` skill → schedules a daily cron check → sends Telegram alert on trigger
- Tools: Playwright + cron scheduler + Telegram notification

#### 📰 News Monitor & Daily Briefing
- "Every morning at 8am, send me a 5-bullet summary of tech and AI news"
- Agent: uses `rss-reader` + `news-monitor` → fetches from configured sources → summarizes with LLM → pushes to Telegram
- Automation: systemd timer or built-in OpenClaw scheduler

#### 🛠️ Utility Tool & App Creator
- "Build me a Python script that converts any YouTube URL to an MP3 and saves it to ~/Music"
- Agent: uses `code-runner` skill → writes, tests, and saves the script → returns it via Telegram file upload
- More examples: currency converters, markdown-to-PDF tools, expense trackers

#### 📊 Competitive & Market Intelligence
- "Keep tabs on [company/topic] — alert me if there's a major announcement or news item"
- Agent: monitors RSS feeds + Google Alerts equivalent → filters by keyword relevance → pushes digest

#### 🗓️ Proactive Reminders & Scheduling
- "Remind me to follow up on Project X in 3 days, and remind me about my dentist appointment on Friday morning"
- Agent: uses `scheduler` skill with persistent cron-like entries → sends Telegram pushes at the right time

### 7.3 Custom Skills You Can Build
Skills are simple Markdown (SKILL.md) + optional JS/Python files. Example custom skill:

```markdown
# SKILL: Morning Briefing

Trigger: Every day at 08:00

Steps:
1. Fetch top 5 headlines from NewsAPI for topics: [AI, tech, finance]
2. Fetch current weather for [your city] from wttr.in
3. Check if any tracked prices have dropped
4. Compose a formatted Telegram message with all findings
5. Send the message to the user
```

---

## Phase 8 — Agent Persona & Memory

### 8.1 System Prompt (Persona)
Customize the agent's behavior in `config.yaml`:
```yaml
system_prompt: |
  You are my personal AI assistant running on my home server.
  You are proactive, concise, and action-oriented.
  When I give you a task, complete it autonomously using available tools.
  Always summarize results in bullet points unless I ask otherwise.
  If a task requires internet access, always check credibility of sources.
  Never take destructive actions (delete files, send messages on my behalf) 
  without explicit confirmation from me.
```

### 8.2 Persistent Memory
OpenClaw supports multiple memory backends:
- **SQLite** (default) — great for most personal use
- **Chroma / Qdrant** (vector DB) — for semantic memory ("remember what I said about X last week")
- **Plain files** — simplest, fully portable

Enable vector memory for smarter recall:
```bash
npx clawhub@latest install memory-vector
```

---

## Phase 9 — Monitoring & Reliability

### 9.1 Health Monitoring
```bash
# Install lightweight monitoring
pip install glances
# Or use the built-in Clawdbot status command
clawdbot status

# systemd auto-restart is already configured — view logs:
journalctl -u clawdbot -f
journalctl -u ollama -f
journalctl -u litellm -f
```

### 9.2 Watchdog Script
Create a simple watchdog that checks all three services and restarts any that have died:
```bash
# /home/aiagent/watchdog.sh
#!/bin/bash
for svc in ollama litellm clawdbot; do
  if ! systemctl is-active --quiet $svc; then
    systemctl restart $svc
    # Optional: send Telegram alert via curl
  fi
done
```
Schedule with crontab: `*/5 * * * * /home/aiagent/watchdog.sh`

### 9.3 Backup Strategy
- **Daily backup** of `/home/aiagent/clawdbot-data` to an external USB or cloud (rclone → Google Drive/Backblaze)
- **Config backup** — keep `config.yaml` and skill files in a private GitHub repo

### 9.4 Power & Uptime
- Use a **UPS (Uninterruptible Power Supply)** mini-UPS for Pi ($15-30) — prevents filesystem corruption on power cuts
- Enable `systemd` auto-start on boot for Clawdbot + Ollama
- Consider a `wtmp` cron to auto-reboot the Pi weekly during low-use hours

---

## Phase 10 — Multi-Model Management & Evolution

> This phase makes the agent smarter over time without breaking anything. The LiteLLM layer you set up in Phase 2 is what makes all of this easy to add later.

### 10.1 Adding New Models

```bash
# Pull and test a new model
ollama pull llama3.2:3b
ollama run llama3.2:3b "Explain the difference between REST and GraphQL"

# Add it to LiteLLM config without touching Clawdbot
# Edit /home/aiagent/litellm_config.yaml:
#   - model_name: coding
#     litellm_params:
#       model: ollama/llama3.2:3b
#       api_base: http://localhost:11434

sudo systemctl restart litellm
# Clawdbot now has access to the new model — no Clawdbot restart needed
```

### 10.2 Automated Model Updates (Script)
```bash
# /home/aiagent/update_models.sh
#!/bin/bash
# Run weekly via cron to keep models up to date
# Only pull models that fit in 4GB RAM headless config
MODELS=("gemma2:2b" "tinyllama")
for model in "${MODELS[@]}"; do
  echo "Updating $model..."
  ollama pull $model
done
echo "All models updated."
```
```
# crontab entry — run every Sunday at 3am
0 3 * * 0 /home/aiagent/update_models.sh >> /var/log/model_updates.log 2>&1
```

### 10.3 Task-Based Model Routing (Advanced)
Use LiteLLM's routing configuration to automatically select the right model per task type. This can be driven by a prefix convention in your Clawdbot skills:

```yaml
# litellm_config.yaml — advanced routing (for Pi 4B with 2 models)
router_settings:
  routing_strategy: usage-based-routing
  model_group_alias:
    default: ["gemma2:2b"]        # All standard tasks
    fast: ["tinyllama"]            # Quick lookups, health checks

  # Unlock these when you upgrade to Pi 5 8GB:
  # reasoning: ["qwen2.5:3b"]
  # coding: ["qwen2.5:3b", "llama3.2:3b"]
```

Clawdbot skills can specify which model group to use in their SKILL.md:
```markdown
# SKILL: Code Generator
model: coding    # Routes to qwen2.5:3b or llama3.2:3b via LiteLLM
```

### 10.4 Model Benchmarking on Your Hardware
Before adopting a new model permanently, benchmark it against your current default:
```bash
# Quick benchmark script
ollama run gemma2:2b "Write a 200-word essay on self-hosting" --verbose 2>&1 | grep "eval rate"
ollama run tinyllama "Write a 200-word essay on self-hosting" --verbose 2>&1 | grep "eval rate"
```
Track tokens/sec, response quality, and RAM usage. Keep a simple log.

### 10.5 Future Enhancement Roadmap

**Current hardware tier (Pi 4B 4GB):**

| Version | Feature | Effort |
|---|---|---|
| **v1.0** | Ollama (Gemma2 2B + TinyLlama) + LiteLLM + Clawdbot + Telegram | Day 1 |
| **v1.1** | Tailscale secure SSH access | 30 min |
| **v1.2** | browser-automation + web-search + rss-reader skills | 1 hour |
| **v1.3** | Pi-hole DNS filtering | 1 hour |
| **v2.0** | Custom skills: morning briefing, price tracker | 2-4 hours |
| **v2.1** | Vector memory (Chroma) for semantic recall | 1 hour |
| **v2.2** | Scheduled proactive tasks (8am news, price alerts) | 2 hours |
| **v2.3** | Automated weekly model updates via cron | 30 min |
| **v3.0** | Multi-skill pipelines (research → report → notify) | 3-5 hours |
| **v3.1** | Voice interface via Telegram voice messages | 2-3 hours |

**QoL Hardware Upgrades (unlock the next tier):**

| Upgrade | Cost (NZD) | What It Unlocks |
|---|---|---|
| **Portable USB SSD 256GB** (e.g. Transcend ESD310C) | ~$179 | Faster model loading, SSD-backed swap, store 5-10+ models, better write endurance |
| **Pi 5 8GB** (board only) | ~$364 | Qwen2.5 3B, Phi-3 Mini, ~2.5× faster inference, stable 3B models |
| **Pi 5 + NVMe HAT + SSD** | ~$480-500 | Full setup: best storage + 3B models + room for future 7B with swap |

**Unlock these after Pi 5 8GB upgrade:**

| Version | Feature | Effort |
|---|---|---|
| **v4.0** | Add Qwen2.5 3B + Phi-3 Mini to LiteLLM routing | 30 min |
| **v4.1** | Task-based model routing (reasoning/coding groups) | 1-2 hours |
| **v4.2** | Open WebUI dashboard for local chat + model management | 1 hour |
| **v5.0** | Fine-tuned model on your own data/preferences | Advanced |

---

## Best Practices Summary

### Security
- ✅ SSH key-only access; disable password SSH
- ✅ Telegram allowlist = your user ID only
- ✅ Run agent as non-root user
- ✅ Never hard-code API keys — use `.env` files excluded from git
- ✅ Firewall all inbound traffic; use Tailscale for admin access
- ✅ Review community skills before installing (read source code)
- ✅ Run browser automation in Docker sandbox

### Privacy
- ✅ Use Ollama local models for sensitive tasks
- ✅ Pi-hole DNS filtering to block telemetry
- ✅ Don't log conversation content to public services
- ✅ Store memory/data only on your Pi

### Reliability
- ✅ systemd service with auto-restart for Ollama, LiteLLM, and Clawdbot
- ✅ Daily backup of agent data directory
- ✅ Mini UPS for power protection
- ✅ Watchdog cron for all three services
- ✅ LiteLLM fallback: if preferred model fails, route to next in group

### Cost
- ✅ **Zero API costs** — all inference is local via Ollama
- ✅ Gemini free tier (1,500 req/day) available as optional fallback only if local LLM is insufficient for a specific task
- ✅ Brave Search API free tier (2,000 queries/month) for web search
- ✅ Tailscale free personal plan (up to 100 devices)
- ✅ All software used (Ollama, LiteLLM, Clawdbot, Pi-hole, Tailscale) is free/open-source

---

## Shopping List

### What You Already Have ✅
| Item | Status |
|---|---|
| Raspberry Pi 4B 4GB | ✅ You have this |
| 32GB SD Card or USB Drive | ✅ You have this |

### What Helps Now (Optional but Recommended)
| Item | Est. Cost (NZD) | Where to Buy | Why |
|---|---|---|---|
| Heatsink + small fan for Pi 4B | ~$15-25 | Jaycar, PB Tech, AliExpress | Prevent thermal throttling during LLM inference |
| Ethernet cable (Cat5e/Cat6, 2m) | ~$10-15 | Jaycar, The Warehouse | More reliable than WiFi for always-on use |

### Future QoL Upgrades (When Ready)
| Item | Est. Cost (NZD) | Where to Buy | What It Unlocks |
|---|---|---|---|
| Portable USB SSD 256GB (e.g. Transcend ESD310C) | ~$179 | PB Tech | Faster model loads, store 5-10+ models, better write endurance |
| Raspberry Pi 5 8GB | ~$364 | PB Tech | 3B models, ~2.5× faster inference |
| NVMe HAT + SSD 256GB (for Pi 5) | ~$80-120 | PB Tech | Best-in-class Pi storage |
| Mini UPS for Pi (e.g. PiSugar or UPS HAT) | ~$50-80 | AliExpress, PB Tech | Power cut protection, prevent filesystem corruption |

> **NZ note**: PB Tech (pbtech.co.nz) is the best local source for Pi hardware. Jaycar stocks basic components (heatsinks, cables). AliExpress is cheapest for accessories but add 3-4 weeks shipping. All prices include GST.

---

## Key Resources & References

- **Clawdbot GitHub**: https://github.com/Clapps/clawdbot
- **OpenClaw Install Guide (Pi)**: https://agentinstaller.com/docs/install/raspberry-pi
- **Raspberry Pi Blog — OpenClaw**: https://www.raspberrypi.com/news/turn-your-raspberry-pi-into-an-ai-agent-with-openclaw/
- **OpenClaw + Ollama (offline)**: https://www.flyenv.com/guide/openclaw.html
- **Clawdbot + Docker**: https://www.docker.com/blog/clawdbot-docker-model-runner-private-personal-ai/
- **Secure Self-Hosting (Shellntel)**: https://blog.shellntel.com/p/installing-openclaw-moltbot-clawdbot-securely-on-a-raspberry-pi5
- **Skills Registry**: https://openclawskills.net/ and https://github.com/VoltAgent/awesome-openclaw-skills
- **Tailscale for Pi**: https://tailscale.com/download/linux
- **Ollama Models**: https://ollama.com/library
- **Brave Search API**: https://brave.com/search/api/
- **NewsAPI (free tier)**: https://newsapi.org/
- **LiteLLM Proxy Docs**: https://docs.litellm.ai/docs/proxy/quick_start
- **Ollama Model Library**: https://ollama.com/library
- **Open WebUI (local model chat UI)**: https://github.com/open-webui/open-webui

---
*Plan created: April 2026 | Location: New Zealand | All prices in NZD incl. GST*
