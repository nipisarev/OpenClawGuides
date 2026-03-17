# OpenClaw: VPS Setup Guide

A step-by-step guide for self-hosting an AI assistant on your own server.

---

## Table of Contents

- [Phase 0: What is OpenClaw](#phase-0-what-is-openclaw)
- [Phase 1: Getting a Server](#phase-1-getting-a-server)
  - [Primary Path: Automated Installer](#primary-path-automated-installer)
  - [Fallback: Manual Steps](#fallback-manual-steps)
- [Phase 2: Securing the Server](#phase-2-securing-the-server) *(automated by installer)*
- [Phase 3: Installing OpenClaw](#phase-3-installing-openclaw) *(automated by installer)*
  - [Manual Installation](#manual-installation)
- [Phase 4: First Agent — Quick Start](#phase-4-first-agent--quick-start) *(automated by installer)*
- [Phase 5: Agent Team](#phase-5-agent-team)
- [Phase 6: Maintenance and Monitoring](#phase-6-maintenance-and-monitoring)

---

## Phase 0: What is OpenClaw

### What We Are Doing and Why

OpenClaw is a platform for running a personal AI assistant on your own server. You send a message in Telegram or WhatsApp, it reaches your server, the server forwards the request to an AI model (Claude, GPT, or another), receives the response, and sends it back to you in the messenger.

Why is this needed if you can just open ChatGPT in a browser? Three reasons:

**Privacy.** Your messages are stored on your server. Only requests to the AI model go outward — and nothing else. No intermediary sees your conversations.

**Availability.** The assistant works 24/7 right in your familiar messenger. No need to open a separate website or application.

**Multi-agent capability.** On a single server, you can run multiple AI assistants with different skills. One answers questions, another writes code, a third reads and summarizes documents — and each one runs in an isolated container (an isolated environment, like a separate apartment in a high-rise: neighbors cannot enter each other's units).

### Diagram

```
┌──────────┐         ┌──────────────────────────────────┐         ┌──────────────┐
│          │         │       Your VPS Server            │         │              │
│   You    │         │                                  │         │  AI Provider  │
│          │  mes-   │  ┌────────────────────────────┐  │ request │  (Claude,    │
│ Telegram ├────────►│  │     OpenClaw Gateway       │  ├────────►│   GPT, etc.) │
│   or     │  sage   │  │                            │  │         │              │
│ WhatsApp │◄────────┤  │  ┌────────┐  ┌────────┐   │  │◄────────┤              │
│          │ response│  │  │Agent 1 │  │Agent 2 │   │  │ response│              │
│          │         │  │  └────────┘  └────────┘   │  │         │              │
└──────────┘         │  └────────────────────────────┘  │         └──────────────┘
                     │                                  │
                     │  Messages stay here.             │
                     │  Only requests to the AI model   │
                     │  go outward.                     │
                     └──────────────────────────────────┘
```

**Gateway** (the central hub) — the main OpenClaw process. It runs continuously on the server, receives messages from messengers, routes them to the appropriate agent, and returns responses.

**Agent** — an AI assistant with an assigned role. Each agent is a combination of an AI model, a set of instructions, and a list of permitted tools. Agents run in isolated Docker containers (software "boxes" that prevent one agent from affecting another or the server itself).

### What You Will Need

| What | Why | Where to Get |
|------|-----|--------------|
| VPS server (a virtual server running in a data center 24/7 — like a computer, but in the cloud) | A place where OpenClaw will live | Hetzner, DigitalOcean, Aeza — see Phase 1 |
| Telegram account | The messenger through which you will communicate with the assistant | telegram.org |
| AI provider API key (a secret code for accessing the AI model — like a service password) | So your server can send requests to Claude or GPT | console.anthropic.com or platform.openai.com |
| Approximately 15-25 min with installer, 30-40 min manually | For the entire installation from start to a working assistant | — |

### Security Principle

OpenClaw is designed with the principle of "maximum isolation by default":

- **Your messages** are stored only on your server.
- **Outward** only requests to the AI model (Claude, GPT) go out — and nothing else.
- **Gateway** listens only on localhost (only "inside" the server — it cannot be connected to from outside).
- **Each agent** runs in a separate Docker container with minimal privileges.
- **Remote access** — only through VPN (an encrypted tunnel, like a secret passage that only you use).

### Multi-Agent Architecture

On a single server, you can run multiple AI assistants, each with its own specialization:

```
┌──────────────────── Single VPS Server ──────────────────┐
│                                                          │
│  ┌─ OpenClaw Gateway ────────────────────────────────┐  │
│  │                                                    │  │
│  │  ┌──────────────┐  ┌──────────────┐               │  │
│  │  │  Assistant    │  │   Coder      │               │  │
│  │  │  Claude       │  │   GPT-4o     │               │  │
│  │  │  General      │  │   Writes code│               │  │
│  │  │  questions    │  │   in sandbox │               │  │
│  │  └──────────────┘  └──────────────┘               │  │
│  │                                                    │  │
│  │  ┌──────────────┐  ┌──────────────┐               │  │
│  │  │  Reader       │  │  Researcher  │               │  │
│  │  │  Claude       │  │  GPT-4o      │               │  │
│  │  │  Document     │  │  Web search  │               │  │
│  │  │  summaries    │  │              │               │  │
│  │  └──────────────┘  └──────────────┘               │  │
│  │                                                    │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  Telegram ──► Assistant (default)                        │
│               /coder ──► Coder                           │
│  WhatsApp ──► Assistant                                  │
└──────────────────────────────────────────────────────────┘
```

Each agent is isolated: it has its own API key, its own set of tools, and its own container. If one agent is compromised — the others are unaffected.

### Trust Boundaries

OpenClaw is designed as a **personal assistant** — one Gateway = one user. Any authorized client gets full operator rights over the entire gateway. There is no role separation within a single Gateway.

| Scenario | Security | Explanation |
|----------|----------|-------------|
| Single user, multiple agents | Safe | Standard operating mode. Docker isolation + tool policies limit damage |
| Two trusted family members | Moderate risk | No session isolation — each person sees the other's history |
| Team/organization on one Gateway | Unsafe | No role separation, no separate auditing, credentials visible to all |

If you need access for multiple users — deploy separate Gateways for each.

### Links

- OpenClaw repository: https://github.com/openclaw/openclaw
- Threat model and security: https://github.com/centminmod/explain-openclaw
- Community guides: https://github.com/xianyu110/awesome-openclaw-tutorial

### Verification

This phase is introductory. If you have read this far and understand the general diagram (message → your server → AI provider → response back), then you are ready for the next step.

### Common Issues

There are no practical steps in this phase, so no issues should arise. If anything described above is unclear — reread the "What We Are Doing and Why" section and study the diagram.

---

## Phase 1: Getting a Server

### What We Are Doing and Why

We need a VPS (Virtual Private Server — a virtual server in a data center that runs around the clock, like a remote computer accessible via the internet). OpenClaw will live on it.

If you already have a VPS with Ubuntu 22.04 or Debian 12 and you can connect to it via SSH — skip directly to Phase 2.

If not — follow the steps below.

### Primary Path: Automated Installer

If you have a VPS with root SSH access, you can use the automated installer to handle Phases 1-4 in one step.

**Prerequisites:**
- VPS with root SSH access (Ubuntu 22.04 or Debian 12)
- Tailscale auth key (get one at https://login.tailscale.com/admin/settings/keys)
- Anthropic API key (from https://console.anthropic.com)
- Telegram bot token (from @BotFather)

**Steps:**

1. SSH into your server as root:

```bash
ssh root@your_ip_address
```

2. Run the installer:

```bash
curl -fsSL https://raw.githubusercontent.com/openclaw/openclaw/main/install.sh | bash
```

The installer will prompt you for the prerequisites listed above and automatically handle:
- Server hardening (Phase 2)
- OpenClaw installation and configuration (Phase 3)
- First agent setup (Phase 4)

After the installer completes, skip to [Phase 5: Agent Team](#phase-5-agent-team).

---

### Fallback: Manual Steps

If you prefer to understand every step or the installer does not suit your needs, follow the manual steps below.

### Diagram

```
┌──────────────┐                              ┌──────────────────┐
│              │        SSH connection         │                  │
│  Your        │  (encrypted management       │  VPS Server      │
│  computer    │   channel to the server)      │  Ubuntu 22.04    │
│              ├─────────────────────────────► │                  │
│  Terminal    │   ssh user@123.45.67.89      │  2 GB RAM        │
│              │                               │  20 GB SSD       │
└──────────────┘                              └──────────────────┘
```

### Minimum Server Requirements

| Parameter | Minimum | Recommended |
|-----------|---------|-------------|
| RAM (memory) | 2 GB | 4 GB |
| CPU (processor) | 1 core | 2 cores |
| Disk | 20 GB SSD | 40 GB SSD |
| OS (operating system) | Ubuntu 22.04 or Debian 12 | Ubuntu 22.04 — easier for beginners |

### Choosing a Provider

| Provider | Min. Price | Location | Features |
|----------|-----------|----------|----------|
| Hetzner | ~4 EUR/mo | Germany, Finland | Best price/quality ratio, stable infrastructure |
| DigitalOcean | ~6 USD/mo | USA, Europe, Asia | Simple interface, extensive documentation |
| Aeza | ~200 RUB/mo | Russia, Europe | Russian-language support, payment in rubles |

Any provider will work for this guide. The examples below are written in a general form.

### Steps

#### Step 1. Register with your chosen provider

Go to the provider's website and create an account. You will need an email and a payment method.

- Hetzner: https://www.hetzner.com/cloud
- DigitalOcean: https://www.digitalocean.com
- Aeza: https://aeza.net

#### Step 2. Generate an SSH key

An SSH key is a digital pass for logging into the server. Instead of a password (which can be guessed), a pair of files is used: a public key (a lock that you place on the server) and a private key (a key that stays only with you). Guessing such a "key" is practically impossible.

Open a terminal (a program for entering commands) on your computer and run the command:

**macOS and Linux** — open the Terminal application:

```bash
ssh-keygen -t ed25519 -C "openclaw-vps"
```

**Windows** — open Windows Terminal or PowerShell (press Win, type "PowerShell", open it):

```powershell
ssh-keygen -t ed25519 -C "openclaw-vps"
```

Press Enter for all prompts (default path, empty passphrase for now).

Expected output:

```
Generating public/private ed25519 key pair.
Enter file in which to save the key (/Users/yourname/.ssh/id_ed25519):
Enter passphrase (empty for no passphrase):
Enter same passphrase again:
Your identification has been saved in /Users/yourname/.ssh/id_ed25519
Your public key has been saved in /Users/yourname/.ssh/id_ed25519.pub
The key fingerprint is:
SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx openclaw-vps
```

Now display the public key so you can copy it:

```bash
cat ~/.ssh/id_ed25519.pub
```

Expected output — a string like:

```
ssh-ed25519 AAAAC3Nza... openclaw-vps
```

Copy this string in its entirety. It will be needed in the next step.

#### Step 3. Create a server

In the provider's control panel, create a new server with the following parameters:

- **OS:** Ubuntu 22.04
- **Plan:** minimum 2 GB RAM, 1 vCPU, 20 GB SSD
- **Region:** closest to you (for minimal latency)
- **SSH key:** paste the public key from the previous step (the string `ssh-ed25519 AAAAC3Nza... openclaw-vps`)
- **Server name:** anything, for example `openclaw`

After creation, the provider will show the IP address (a set of numbers like `123.45.67.89`) of your server. Write it down.

#### Step 4. Connect to the server

SSH (Secure Shell) — an encrypted connection for remote server management. You type commands on your computer, and they are executed on the server.

Wait 1-2 minutes after creating the server (it needs time to start up) and run:

```bash
ssh root@your_ip_address
```

Replace `your_ip_address` with the IP the provider showed you. For example: `ssh root@123.45.67.89`.

On the first connection, the system will ask:

```
The authenticity of host '123.45.67.89' can't be established.
ED25519 key fingerprint is SHA256:xxxxxxxxxxx.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

Type `yes` and press Enter. This is a normal question on the first connection — the system remembers the server's "fingerprint."

Expected output — the server command prompt:

```
root@openclaw:~#
```

You are inside the server.

#### Step 5. Update the system

The first thing to do on a fresh server is to install all security updates:

```bash
apt update && apt upgrade -y
```

`apt` is the package manager (a program for installing and updating software on Ubuntu/Debian). `update` downloads the list of updates, `upgrade` installs them. The `-y` flag means "answer 'yes' to all questions automatically."

Expected output — a list of updated packages, ending with something like:

```
XX upgraded, XX newly installed, 0 to remove and 0 not upgraded.
```

#### Step 6. Create a regular user

Right now you are working as `root` — a user with unrestricted privileges. This is like walking around a building with a master key for all doors: convenient, but dangerous — any mistake or breach can damage the entire system.

Principle of least privilege: for everyday work, use a regular user, and request `root` privileges only when needed (via the `sudo` command).

Create a new user:

```bash
adduser openclaw
```

The system will ask you to set a password and fill in user information. Set a strong password; the other fields can be left empty (press Enter).

Expected output:

```
Adding user `openclaw' ...
Adding new group `openclaw' (1001) ...
Adding new user `openclaw' (1001) with group `openclaw' ...
Creating home directory `/home/openclaw' ...
Copying files from `/etc/skel' ...
New password:
Retype new password:
passwd: password updated successfully
...
Is the information correct? [Y/n] Y
```

Give the new user the right to execute commands as administrator via `sudo` (a command that allows a regular user to execute a single specific command with root privileges — instead of being root all the time):

```bash
usermod -aG sudo openclaw
```

#### Step 7. Set up SSH access for the new user

Copy your SSH key from the root user to the new user, so you can log into the server directly under the new account:

```bash
mkdir -p /home/openclaw/.ssh
cp /root/.ssh/authorized_keys /home/openclaw/.ssh/authorized_keys
chown -R openclaw:openclaw /home/openclaw/.ssh
chmod 700 /home/openclaw/.ssh
chmod 600 /home/openclaw/.ssh/authorized_keys
```

What each command does:
- `mkdir -p` — creates the `.ssh` directory in the new user's home directory
- `cp` — copies the authorized keys file from root to the new user
- `chown -R` — transfers file ownership to the new user (otherwise SSH will deny access)
- `chmod 700` and `chmod 600` — set strict file access permissions (only the owner can read and modify)

#### Step 8. Disconnect and reconnect as the new user

Log out of the server:

```bash
exit
```

Connect again, but now as the `openclaw` user:

```bash
ssh openclaw@your_ip_address
```

Expected output:

```
openclaw@openclaw:~$
```

Notice: instead of `root@`, it now shows `openclaw@` — you are logged in as a regular user. For commands requiring administrator privileges, use `sudo` before the command.

### Verification

Run the following command to make sure everything works:

```bash
whoami && sudo whoami
```

Expected output:

```
openclaw
root
```

The first line is your current user (`openclaw`). The second confirms that `sudo` works (the `whoami` command was executed as `root`). On first use of `sudo`, the system will ask for the `openclaw` user's password.

If you see both lines — the server is ready. Proceed to Phase 2.

### Common Issues

**"Connection refused" when trying to connect via SSH**

The server has not booted yet. Wait 2-3 minutes after creation and try again. If that does not help — verify the IP address in the provider's control panel.

**"Permission denied (publickey)" when connecting**

The SSH key was not added when creating the server, or was added incorrectly. Solutions:
- Make sure you copied the public key (the file with the `.pub` extension).
- In the provider's control panel, delete the server, re-add the SSH key, and create the server again.
- If the provider allows it — open the server's web console and add the key manually.

**Cannot find the terminal on Windows**

Press the `Win` key on your keyboard, type `PowerShell`, and open the found program. If you have Windows 11 — you can also find "Windows Terminal" (a more convenient option). All SSH commands work identically in both programs.

**"sudo: command not found" for the new user**

On some minimal Debian images, `sudo` is not pre-installed. Log in as `root` and install it:

```bash
ssh root@your_ip_address
apt install -y sudo
usermod -aG sudo openclaw
exit
```

Then log in again as `openclaw`.

**Forgot the new user's password**

Log in as `root` and reset the password:

```bash
ssh root@your_ip_address
passwd openclaw
exit
```

### Links

- Hetzner Cloud documentation: https://docs.hetzner.com/cloud/servers/getting-started/creating-a-server
- DigitalOcean guide on initial server setup: https://www.digitalocean.com/community/tutorials/initial-server-setup-with-ubuntu-22-04
- Ubuntu Server guide: https://ubuntu.com/server/docs
- Aeza guide: https://wiki.aeza.net

---

## Phase 2: Securing the Server

> **Automated:** The installer handles this phase automatically. If you used the installer, skip to Phase 5.

### What We Are Doing and Why

Right now your server is like a house with open doors — anyone can try to walk in. In this phase, we build five layers of protection so that even if one layer is breached, the others continue to work. This is called "defense in depth" — when one line of defense fails, the next one stands behind it.

### Diagram

```
Internet
    │
    ▼
┌──────────────────────────────────────────────────────────────────┐
│  Layer 1: UFW firewall — blocks everything except SSH & Tailscale│
├──────────────────────────────────────────────────────────────────┤
│  Layer 2: Fail2ban — bans IP after 5 failed login attempts       │
├──────────────────────────────────────────────────────────────────┤
│  Layer 3: Tailscale VPN — private network, server is invisible   │
├──────────────────────────────────────────────────────────────────┤
│  Layer 4: SSH key-only — passwords completely disabled           │
├──────────────────────────────────────────────────────────────────┤
│  Layer 5: Auto-updates — security holes are patched automatically│
└──────────────────────────────────────────────────────────────────┘
    │
    ▼
Your server — secured
```

### Safety Prerequisites (READ BEFORE STARTING PHASE 2)

Before making any security changes, prepare your escape hatch:

1. **Know your VPS provider's web console URL** — this is your last resort if you lock yourself out:
   - Hetzner: https://console.hetzner.cloud
   - DigitalOcean: https://cloud.digitalocean.com
   - Aeza: https://my.aeza.net
2. **Open the web console in a separate browser tab RIGHT NOW** before proceeding. Verify you can access it.
3. **RULE: NEVER close your current SSH session during Phase 2.** All testing must happen in NEW terminal windows. Your original session is your lifeline.

#### Safety Checkpoints

| After Step | Check | If Failed |
|-----------|-------|-----------|
| UFW enable | Can you SSH from a NEW terminal? | Run `sudo ufw disable` in your ORIGINAL terminal |
| SSH restart | Key login works AND password is denied? | Restore backup in original terminal (see instructions below) |
| Before chattr | Can you SSH from 2+ different devices/networks? | Fix access before locking config |

### Steps

#### Step 1. Configure the UFW firewall

A firewall — is a guard at the entrance to your server. It decides which network traffic to allow and which to block. UFW (Uncomplicated Firewall) is a simplified utility for managing this guard.

**1.1. Deny all incoming connections by default:**

```bash
sudo ufw default deny incoming
```

This command tells the firewall: "block absolutely everything coming from outside unless I explicitly allow it." This is the safest initial state.

Expected output:
```
Default incoming policy changed to 'deny'
```

**1.2. Allow SSH connections:**

```bash
sudo ufw allow 22/tcp
```

A port is a numbered "door" on the server. Port 22 is the standard door for SSH. If you do not open it, you will not be able to connect to the server after enabling the firewall.

Expected output:
```
Rules updated
Rules updated (v6)
```

**1.3. Allow Tailscale:**

```bash
sudo ufw allow 41641/udp
```

Port 41641 is needed for Tailscale VPN, which we will set up in step 3. UDP is a type of network protocol (unlike TCP, it is faster but less reliable; for VPN this is the optimal choice).

Expected output:
```
Rules updated
Rules updated (v6)
```

> **⚠️ CRITICAL: DO NOT CLOSE YOUR CURRENT SSH SESSION**
>
> After enabling UFW, test connectivity from a **NEW** terminal window.
> Keep your current session open as a lifeline until you confirm access works.

**1.4. Enable the firewall:**

```bash
sudo ufw enable
```

The system will ask for confirmation — type `y` and press Enter.

Expected output:
```
Command may disrupt existing SSH connections. Proceed with operation (y|n)? y
Firewall is active and enabled on system startup
```

The firewall will now start automatically on every server reboot.

> **🛑 STOP POINT — Verify SSH Access**
>
> Open a **new terminal** and try to SSH into your server:
> ```bash
> ssh openclaw@YOUR_SERVER_IP
> ```
> - ✅ If it works: proceed to the next step
> - ❌ If it fails: run `sudo ufw disable` in your **original** terminal, then troubleshoot
>
> **Do NOT proceed until this test passes.**

---

#### Step 2. Install Fail2ban

Fail2ban is an automatic blocker. It monitors login logs and, if someone tries to guess your password multiple times in a row, blocks their IP address (IP address — a unique number for each device on the internet, like a postal code).

**2.1. Installation:**

```bash
sudo apt update && sudo apt install -y fail2ban
```

Expected output — a long list of lines ending with:
```
Setting up fail2ban ...
```

**2.2. Create a configuration file:**

Fail2ban stores its settings in the `/etc/fail2ban/` directory. The `jail.local` file contains your custom rules, which will not be overwritten during program updates.

```bash
sudo tee /etc/fail2ban/jail.local << 'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
maxretry = 5
bantime = 3600
findtime = 600
EOF
```

What these settings mean:
- `enabled = true` — SSH protection is enabled
- `maxretry = 5` — after 5 failed login attempts, the IP is blocked
- `bantime = 3600` — blocked for 3600 seconds (1 hour)
- `findtime = 600` — the 5 attempts must occur within 600 seconds (10 minutes) for the block to trigger

**2.3. Start and enable auto-start:**

```bash
sudo systemctl enable --now fail2ban
```

The `systemctl` command manages operating system services. The `enable` flag turns on auto-start on reboot, and `--now` starts the service right away.

Expected output:
```
Synchronizing state of fail2ban.service...
```

**2.4. Verify that Fail2ban is working:**

```bash
sudo fail2ban-client status sshd
```

Expected output:
```
Status for the jail: sshd
|- Filter
|  |- Currently failed: 0
|  `- Total failed:     0
`- Actions
   |- Currently banned: 0
   `- Total banned:     0
```

---

#### Step 3. Set up Tailscale VPN

Instead of your server being visible to the entire internet, a VPN (Virtual Private Network) creates a private tunnel. Imagine: right now your server stands on a busy street with a sign saying "I'm here." With a VPN, you hide it in a closed courtyard, and only your devices have the key to the gate.

Tailscale is the simplest VPN for our task. It uses WireGuard technology and requires no complex configuration.

**3.1. Create a Tailscale account:**

Open https://login.tailscale.com/start in your browser and register. You can sign in with a Google, GitHub, or Microsoft account.

**3.2. Install Tailscale on the VPS:**

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

This command downloads and runs the installer. `curl` is a utility for downloading files from the internet. The `-fsSL` flags mean: do not show a progress bar, but show errors, and follow redirects.

Expected output ends with the line:
```
Installation complete.
```

**3.3. Connect the VPS to your Tailscale network:**

```bash
sudo tailscale up
```

The command will output an authorization link:
```
To authenticate, visit:

    https://login.tailscale.com/a/abc123...
```

Open this link in a browser on your computer and confirm the connection.

**3.4. Find out the Tailscale IP of your server:**

```bash
tailscale ip -4
```

Expected output — an IP address like:
```
100.x.y.z
```

Write down this address — you will use it to connect to the server via VPN.

**3.5. Install Tailscale on your device (computer or phone):**

- **macOS/Windows/Linux:** download from https://tailscale.com/download
- **iOS:** App Store, search for "Tailscale"
- **Android:** Google Play, search for "Tailscale"

After installation, sign in with the same account as in step 3.1.

**3.6. Verify the VPN connection:**

From your device (not from the VPS itself), connect to the server via the Tailscale IP:

```bash
ssh your_user@100.x.y.z
```

Replace `100.x.y.z` with the address from step 3.4, and `your_user` with your username on the server.

If the connection was successful, you have reached the server through a private tunnel.

> **Verify Tailscale from multiple networks:**
> - Test from your home WiFi
> - Test from mobile data (phone hotspot)
> - Both connections must work before relying on Tailscale as your primary access method

---

#### Step 4. Set up automatic security updates

Every day, vulnerabilities are found in software. Auto-updates (unattended-upgrades) are like automatic lock replacements if a defect is found in the old ones.

**4.1. Installation:**

```bash
sudo apt install -y unattended-upgrades
```

**4.2. Enable automatic updates:**

```bash
sudo dpkg-reconfigure -plow unattended-upgrades
```

The system will ask: "Automatically download and install stable updates?" — select `Yes`.

**4.3. Verify that auto-updates are working:**

```bash
sudo unattended-upgrade --dry-run
```

The `--dry-run` flag means "dry run" — the command will show what it *would* update, but will not change anything. If the command completes without errors, auto-updates are configured correctly.

> **Note:** Unattended upgrades may occasionally restart SSH. This is normal but can briefly interrupt connections.
> Monitor the log at `/var/log/unattended-upgrades/` if you experience unexpected disconnections.

---

#### Step 5. Disable password login via SSH

Currently you log into the server via SSH key (configured in Phase 1). But the server still accepts password login as well. This is an extra door that needs to be closed — passwords can be guessed, keys — practically cannot.

**5.1. Open the SSH configuration file:**

```bash
sudo nano /etc/ssh/sshd_config
```

`nano` is a simple text editor in the terminal.

**5.2. Find and modify the following lines:**

Use `Ctrl+W` to search. Find each of these lines and make sure they look exactly like this (without the `#` character at the beginning):

```
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
```

If a line starts with `#` — remove the `#` (this is a comment character that disables the setting). If the value is `yes` instead of `no` — replace it.

Save the file: `Ctrl+O`, then `Enter`, then `Ctrl+X` to exit.

**5.3. Restart the SSH service:**

```bash
sudo systemctl restart sshd
```

Important: do not close the current SSH session! Open a new terminal and verify that you can connect via key. If something went wrong, in the first terminal you can revert the changes.

**5.4. Verify that password login is disabled:**

In a new terminal, try connecting with forced password authentication:

```bash
ssh -o PubkeyAuthentication=no your_user@your_server_IP
```

Expected output:
```
Permission denied (publickey).
```

This means the server denied password access — exactly what we need.

> **🛑 STOP POINT — Verify SSH Configuration**
>
> Run TWO tests from a new terminal:
>
> **Test A — Key authentication must work:**
> ```bash
> ssh openclaw@YOUR_SERVER_IP
> ```
> Expected: login succeeds without password prompt
>
> **Test B — Password authentication must be denied:**
> ```bash
> ssh -o PubkeyAuthentication=no openclaw@YOUR_SERVER_IP
> ```
> Expected: `Permission denied (publickey)` error
>
> **Both tests must pass before proceeding. If Test A fails, restore the SSH backup:**
> ```bash
> sudo chattr -i /etc/ssh/sshd_config  # if already locked
> sudo cp /etc/ssh/sshd_config.backup-openclaw-* /etc/ssh/sshd_config
> sudo systemctl restart sshd
> ```

---

> **⚠️ BEFORE LOCKING SSH CONFIG**
>
> Test SSH access from at least 2 different devices or networks before making the configuration immutable.
> After `chattr +i`, the ONLY way to modify SSH config is via the VPS web console.

#### Step 6. Protecting configuration files from modification

After the SSH settings are locked down, we place a "kernel-level lock" on them — the `chattr +i` attribute (immutable). This attribute prevents file modification even by the root user, as if you put a lock on a door whose key must be explicitly requested each time.

**6.1. Make the configuration files immutable:**

```bash
sudo chattr +i /etc/ssh/sshd_config
sudo chattr +i /root/.ssh/authorized_keys
```

Now these files cannot be modified, deleted, or renamed — not manually, not by a script, not by malware.

**6.2. How to edit protected files**

If in the future you need to modify one of these files, first remove the protection, make changes, then restore the protection:

```bash
sudo chattr -i /etc/ssh/sshd_config
# ... make changes ...
sudo chattr +i /etc/ssh/sshd_config
```

**Important:** Do not use `chattr +i` on OpenClaw configuration files (`openclaw.json`, `paired.json`, etc.) — they must be writable during program operation. For their protection, use `chmod 600` (access only for the owner) and integrity checking via hash sums (baseline).

---

### Verification

Run all checks one after another:

**Firewall:**

```bash
sudo ufw status verbose
```

Expected output:
```
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW IN    Anywhere
41641/udp                  ALLOW IN    Anywhere
22/tcp (v6)                ALLOW IN    Anywhere (v6)
41641/udp (v6)             ALLOW IN    Anywhere (v6)
```

**Tailscale:**

```bash
tailscale status
```

Expected output — a table with your connected devices:
```
100.x.y.z   your-server       your-account@   linux   -
100.a.b.c   your-laptop       your-account@   macOS   -
```

**SSH configuration immutability:**

```bash
lsattr /etc/ssh/sshd_config
```

Expected output:
```
----i------------- /etc/ssh/sshd_config
```

The `i` flag in the output confirms that the file is protected from modification.

**SSH via password (should be denied):**

```bash
ssh -o PubkeyAuthentication=no your_user@your_server_IP
```

Expected output:
```
Permission denied (publickey).
```

### Common Issues

**Issue: Lost access to the server after enabling UFW**

If you accidentally blocked your own SSH access:
1. Log into the server via the **web console** of your VPS provider (Hetzner, DigitalOcean, etc. — look for the "Console" or "VNC" button in the control panel)
2. Run:
```bash
sudo ufw disable
sudo ufw allow 22/tcp
sudo ufw enable
```

The web console works directly, bypassing the network, so the firewall does not affect it.

**Issue: Tailscale is not connecting**

1. Verify that on both devices (VPS and your computer/phone) you are signed into the same Tailscale account
2. On the VPS, check the status:
```bash
sudo systemctl status tailscaled
```
It should say `active (running)`. If not:
```bash
sudo systemctl restart tailscaled
sudo tailscale up
```
3. Make sure port 41641/udp is open in UFW (step 1.3)

**Issue: Fail2ban blocked my IP**

If you entered the wrong password several times and got blocked:
```bash
sudo fail2ban-client set sshd unbanip your_IP_address
```

To find out which IPs are blocked:
```bash
sudo fail2ban-client status sshd
```

**Issue: Cannot log in after disabling passwords**

If password login is disabled and the key is not working:
1. Log in via the VPS provider's web console
2. Re-enable password login:
```bash
sudo nano /etc/ssh/sshd_config
```
Change `PasswordAuthentication no` to `PasswordAuthentication yes`, save and run:
```bash
sudo systemctl restart sshd
```
3. Re-configure the SSH key (following the instructions from Phase 1), then repeat step 5

### Links

- UFW — official Ubuntu documentation: https://help.ubuntu.com/community/UFW
- Fail2ban — official wiki: https://github.com/fail2ban/fail2ban/wiki
- Tailscale — getting started guide: https://tailscale.com/kb/1017/install
- SSH configuration — OpenSSH manual: https://www.openssh.com/manual.html

---

## Phase 3: Installing OpenClaw

> **Automated:** The installer handles this phase automatically. If you used the installer, skip to Phase 5.

### What We Are Doing and Why

The server is secured — now we install the application itself. OpenClaw is a gateway platform that connects messengers (Telegram, WhatsApp) with AI models (Claude, GPT). Your messages are processed on your server; only requests to the AI go outward.

### Diagram

```
VPS
┌──────────────────────────────┐
│                              │
│  Node.js 22.x               │
│  pnpm (package manager)      │
│  Docker CE (containers)      │
│  OpenClaw Gateway            │
│  systemd service             │
└──────────────────────────────┘

All steps below are executed on the VPS, command by command.
```

### Steps

---

### Manual Installation

All commands below are executed **on the VPS** (connect via SSH).

#### Step 1. Install Node.js 22.x

Node.js is a JavaScript runtime environment. OpenClaw is written in JavaScript/TypeScript, and Node.js is required for it to run.

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
```

The first command adds the NodeSource repository (a package source) — it contains the latest version of Node.js. The second installs Node.js from this repository.

Verify:

```bash
node -v
```

Expected output:
```
v22.x.x
```

The number after `v22.` may differ — what matters is that it starts with `22`.

#### Step 2. Install pnpm

pnpm is a package manager for Node.js, analogous to apt but for JavaScript libraries. OpenClaw is distributed through the npm registry, and pnpm is needed for its installation.

```bash
corepack enable
corepack prepare pnpm@latest --activate
```

`corepack` is a built-in Node.js utility for managing package managers.

Verify:

```bash
pnpm -v
```

Expected output — a version number:
```
9.x.x
```

#### Step 3. Install Docker CE

Docker is a containerization platform. A container is like a shipping container on a ship: the program inside is isolated from everything else on the server. If an AI agent runs something dangerous, it happens inside the container and does not affect your server.

```bash
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
```

These commands download and install Docker's cryptographic key — it is needed so your system trusts packages from Docker.

```bash
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

This command adds the Docker repository to your system's package sources list.

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

Installation of Docker itself and its components.

```bash
sudo usermod -aG docker $USER
```

Adds your user to the `docker` group so you can run containers without `sudo`. For the change to take effect, you need to log out and back in:

```bash
exit
ssh your_user@100.x.y.z
```

Verify:

```bash
docker run hello-world
```

Expected output contains the line:
```
Hello from Docker!
This message shows that your installation appears to be working correctly.
```

#### Step 4. Install OpenClaw

```bash
pnpm install -g openclaw
```

The `-g` flag means global installation — the program will be available as a command from any directory.

Verify:

```bash
openclaw --version
```

Expected output — a version number:
```
openclaw v2026.x.x
```

> **Critically important:** The OpenClaw version must be **no lower than v2026.3.12**. Earlier versions contain serious vulnerabilities: CVE-2026-25253 (WebSocket connection hijacking enabling remote code execution even when bound to loopback) and CVE-2026-28472 (authentication bypass). If your version is lower — update with `openclaw update`.

#### Step 5. Register OpenClaw as a systemd service

Create a systemd service so that OpenClaw starts automatically on boot and restarts on failures:

```bash
openclaw service install
```

Verify the service is properly enabled:
```bash
systemctl is-enabled openclaw
```
Expected output: `enabled`

---

### Common Steps (for both paths)

#### Step 6. Apply the hardened configuration

Configuration (config) — a file with program behavior settings. OpenClaw uses the JSON5 format (an extended version of JSON that supports comments).

Open the configuration file:

```bash
nano ~/.openclaw/openclaw.json5
```

Replace the contents with the following:

```json5
{
  "$schema": "https://openclaw.ai/schemas/2024-11/config.json",
  "version": 1,

  "gateway": {
    "bind": "loopback",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "INSERT_TOKEN_FROM_STEP_7_HERE"
    },
    "trustedProxies": [],
    "controlUi": {
      "dangerouslyDisableDeviceAuth": false
    }
  },

  "env": {},

  "session": {
    "dmScope": "per-channel-peer"
  },

  "agents": {
    "defaults": {
      "tools": {
        "profile": "minimal"
      },
      "sandbox": {
        "mode": "all",
        "workspaceAccess": "none"
      }
    }
  },

  "skills": {
    "autoInstall": false,
    "trustedPublishers": []
  },

  "logging": {
    "redactSensitive": "tools"
  },

  "browser": {
    "evaluateEnabled": false
  },

  "discovery": {
    "mdns": {
      "mode": "off"
    }
  },

  "plugins": {
    "enabled": false
  },

  "commands": {
    "config": false
  },

  "channels": {
    "telegram": {
      "linkPreview": false,
      "groups": {
        "*": {
          "requireMention": true,
          "tools": {
            "allow": ["read", "message"],
            "deny": ["exec", "write", "edit", "browser", "gateway", "nodes"]
          }
        }
      }
    }
  }
}
```

What each setting does:

| Setting | Value | Why |
|---------|-------|-----|
| `bind: "loopback"` | Gateway listens only on `127.0.0.1` | Access only through Tailscale, not from the open internet |
| `auth.mode: "token"` | Login by token | Without the token, nobody can access the Gateway |
| `sandbox.mode: "all"` | All agent tools run inside Docker containers | Even if an agent does something dangerous, it will not escape the container |
| `sandbox.workspaceAccess: "none"` | Agents have no access to the file system | No risk of reading or modifying files on the server |
| `tools.profile: "minimal"` | Agents get a minimal set of tools | Fewer tools — fewer opportunities for abuse |
| `redactSensitive: "tools"` | Sensitive data is removed from logs | Tokens and keys will not end up in the log |
| `browser.evaluateEnabled: false` | JavaScript execution in the browser is disabled | Closes the code injection vector |
| `discovery.mdns.mode: "off"` | The server does not announce itself on the network | A VPS does not need local network discovery |
| `plugins.enabled: false` | Plugins are disabled | No third-party code will run until you explicitly allow it |
| `commands.config: false` | Configuration changes via chat are prohibited | Settings are changed only through the terminal on the server |
| `session.dmScope: "per-channel-peer"` | Separate session per channel and peer | Prevents context leakage between users and channels |
| `skills.autoInstall: false` | Skills are not auto-installed | Prevents supply-chain attacks via malicious skills |
| `channels.telegram.linkPreview: false` | Link previews disabled | Blocks data exfiltration via crafted URLs |
| `channels.telegram.groups.*.requireMention: true` | Bot only responds when mentioned in groups | Prevents unintended tool usage by group members |

Do not close the file — first generate the token (step 7), insert it, and only then save.

#### Step 6.5. Limit Gateway resources

In Node.js (the runtime that OpenClaw runs on), there is a known memory leak issue (Issue #13758 — the Gateway can consume up to 1.9 GB of memory after 13 hours of continuous operation). A memory leak is when a program requests memory from the system but never returns it, as if you were taking plates from a cabinet but never putting them back — eventually the cabinet empties.

To prevent the Gateway from "eating" all the server's memory, we limit its resources via systemd:

> **⚠️ Memory limits are NOT optional.** Skipping this configuration can cause a 13-hour memory exhaustion crash that brings down your entire VPS. Always configure the resource limits as shown above.

```bash
# Add Node.js memory limit to systemd service
sudo mkdir -p /etc/systemd/system/openclaw.service.d
sudo tee /etc/systemd/system/openclaw.service.d/resources.conf << 'EOF'
[Service]
Environment=NODE_OPTIONS=--max-old-space-size=1536
MemoryHigh=1536M
MemoryMax=2G
Restart=always
RestartSec=5
EOF
sudo systemctl daemon-reload
sudo systemctl restart openclaw
```

What each setting does:

| Setting | Value | Why |
|---------|-------|-----|
| `--max-old-space-size=1536` | Limits the Node.js heap to 1536 MB | Prevents uncontrolled memory growth |
| `MemoryHigh=1536M` | Soft limit — the system starts actively freeing memory | Slows down the process instead of killing it |
| `MemoryMax=2G` | Hard limit — the process will be restarted if exceeded | Protects the server from freezing |
| `Restart=always` | Automatic restart on any failure | The Gateway will recover without your intervention |

#### Step 6.6. Protect the secrets directory

The `~/.openclaw/` directory stores OAuth tokens (authorization tokens for connected services), session keys, and other secrets in plaintext. If another user on the server gains access to them, they can control your assistant.

```bash
# Protect the secrets directory
chmod 700 ~/.openclaw/
```

Access permissions `700` mean: only the owner can read, write, and enter this directory. All other system users will not even see the list of files inside — like a locked room to which only you have the key.

#### Step 6.7. Configure session isolation

By default, OpenClaw merges the context of all users who message the bot into a single session (dmScope — direct message scope). This means secrets or files uploaded by one user can be read by another. Even if you are the only user, it is recommended to enable isolation:

```bash
openclaw config set session.dmScope per-channel-peer
```

The `per-channel-peer` value creates a separate session for each "channel + peer" combination. Your Telegram messages do not mix with WhatsApp messages, and if someone else writes to your bot — they will not see your conversation.

#### Step 6.8. Restrict tools in group chats

If your bot is added to a group chat, by default all group members can use its tools — including command execution and file access. This is dangerous.

Add group restrictions to the configuration. Open `~/.openclaw/openclaw.json5` and add to the `channels` block:

```json5
"channels": {
  "telegram": {
    "linkPreview": false,
    "groups": {
      "*": {
        "requireMention": true,
        "tools": {
          "allow": ["read", "message"],
          "deny": ["exec", "write", "edit", "browser", "gateway", "nodes"]
        }
      }
    }
  }
}
```

What this does:
- `"*"` — the rule applies to **all** groups
- `requireMention: true` — the bot only responds when mentioned (@bot_name), not to every message
- `deny` — prohibits command execution (`exec`), file writing (`write`, `edit`), browser (`browser`), and gateway management (`gateway`, `nodes`)
- Only reading (`read`) and sending messages (`message`) remain

#### Step 7. Generate an authorization token

A token is a long random string that serves as a password for Gateway access. Unlike a regular password, it is impossible to guess.

```bash
openssl rand -hex 32
```

Expected output — a string of 64 characters (letters and digits):
```
a1b2c3d4e5f6...  (64 characters)
```

Copy this string and paste it into the configuration in place of `INSERT_TOKEN_FROM_STEP_7_HERE`.

Save the configuration file: `Ctrl+O`, `Enter`, `Ctrl+X`.

Important: save the token in a secure location (password manager). If you lose it — you will need to generate a new one.

#### Step 7.1. Authorization token protection

OpenClaw can pass the token via URL parameters (`?token=...`), which leads to leakage through browser history, Referer headers, and proxy logs.

**Token protection rules:**

1. **Token length** — use only `openssl rand -hex 32` (256 bits). OpenClaw does not validate token length — a weak token like `1234` will be accepted, but this is a critical vulnerability
2. **Do not disable device authentication** — the `dangerouslyDisableDeviceAuth: false` setting adds a second layer of protection via one-time pairing codes (a short-lived code that the Gateway displays in the terminal when a new device connects for the first time)
3. **Clear browser history** after first access to the Control UI
4. **Rotate the token regularly** — once a month or if a leak is suspected:

```bash
openclaw config set gateway.auth.token $(openssl rand -hex 32)
```

5. **Never save a URL containing the token** in bookmarks and do not transmit it through messengers

#### Step 8. Put the configuration under version control

Version control — a system that remembers every change in files. If someone (or something) changes your configuration, you can see exactly what changed and revert it.

```bash
cd ~/.openclaw && git init && git add . && git commit -m "baseline"
```

This command:
1. Navigates to the OpenClaw settings directory
2. Initializes a Git repository (a version control system)
3. Adds all files
4. Creates the first "snapshot" — a reference point

Expected output ends with:
```
[main (root-commit) xxxxxxx] baseline
 X files changed, Y insertions(+)
```

In the future, you can check whether the configuration has changed:

```bash
cd ~/.openclaw && git diff
```

If the output is empty — nothing has changed. If there are changes — you will see exactly what was modified.

---

### Verification

**OpenClaw is running:**

```bash
openclaw status
```

Expected output contains:
```
Gateway: running
```

**Security audit passed:**

```bash
openclaw security audit
```

The command checks more than 50 security parameters across 12 categories (file permissions, channel policies, network accessibility, etc.).

Expected output — all checks passed without critical errors.

**Diagnostics without errors:**

```bash
openclaw doctor
```

The `doctor` command is a quick system health check: correct dependency versions, Docker availability, configuration correctness.

Expected output — no lines with `ERROR`.

**Access permissions for the secrets directory:**

```bash
ls -la ~ | grep .openclaw
```

Expected output:
```
drwx------  ... .openclaw
```

The value `drwx------` confirms that only the owner has access to the directory.

### Common Issues

**Issue: Docker does not start**

Check the service status:
```bash
sudo systemctl status docker
```

If the status is not `active (running)`:
```bash
sudo systemctl start docker
sudo systemctl enable docker
```

If Docker gives a `permission denied` error:
```bash
sudo usermod -aG docker $USER
```

After this, you **must** log out and back into the server.

**Issue: Wrong Node.js version**

```bash
node -v
```

If the version does not start with `v22`:
```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
```

**Issue: `openclaw` command not found after installation**

If the terminal says `command not found: openclaw`:
```bash
export PATH="$PATH:$(pnpm bin -g)"
```

To make the change persist after re-login:
```bash
echo 'export PATH="$PATH:$(pnpm bin -g)"' >> ~/.bashrc
source ~/.bashrc
```

**Issue: Permission denied when running OpenClaw**

Make sure you are working under a regular user, not root. OpenClaw deliberately does not run as root for security reasons:
```bash
whoami
```

The output should be your username, **not** `root`. If you are root — log out and log in as a regular user.

**Issue: `openclaw security audit` shows warnings**

Try automatic fixing of safe issues:
```bash
openclaw security audit --fix
```

The command will fix what can be fixed automatically and show the remaining issues that need to be resolved manually.

### Links

- OpenClaw — official website and documentation: https://openclaw.ai
- Docker — installation guide for Ubuntu: https://docs.docker.com/engine/install/ubuntu/
- Node.js — official website: https://nodejs.org
- pnpm — documentation: https://pnpm.io

---

## Phase 4: First Agent — Quick Start

> **Automated:** The installer handles this phase automatically. If you used the installer, skip to Phase 5.

### What We Are Doing and Why

In the previous phases, we prepared the server: installed OpenClaw, configured security, and set up VPN access. But the system is still silent — no messenger and no AI model is connected to it.

In this phase, we will get our first working result: send a message to a bot in Telegram and receive a response from the AI. To do this, we need to do three things: get an access key to the AI service, create a Telegram bot, and link everything together inside OpenClaw.

### Diagram

```
                        Internet
                           │
You (Telegram) ───► Telegram Bot API ───► OpenClaw Gateway ───► Claude/GPT API
                                          (your server)          (AI service)
      ◄── response ◄──────────────── ◄── response ◄───────── ◄── response ◄──
```

### Steps

**Step 1. Get an API key from the AI service**

An API key (Application Programming Interface key) is a password for accessing the AI service, like a Wi-Fi password: without it, your server cannot send requests to Claude or GPT.

Choose one of the options:

*Option A — Claude (Anthropic):*

1. Go to https://console.anthropic.com
2. Register and confirm your email
3. Navigate to the "API Keys" section
4. Link a payment method (card) — AI services charge based on the amount of processed text; the cost of a typical dialog is a few cents
5. Click "Create Key", give the key a descriptive name, for example `openclaw-vps`
6. Copy the key — it is shown only once

*Option B — GPT (OpenAI):*

1. Go to https://platform.openai.com
2. Register and confirm your email
3. Navigate to the "API keys" section
4. Link a payment method
5. Click "Create new secret key", give it the name `openclaw-vps`
6. Copy the key

Security recommendation: set a spending limit in the provider's account settings. Start with $5-10 per month — for personal use, this is sufficient.

IMPORTANT: never send the API key in chats, do not store it in notes or documents with shared access. Treat it like a banking app password.

---

**Step 2. Create a Telegram bot**

A Telegram bot is a special Telegram account controlled by a program (in our case — OpenClaw), not a human. You will send it messages, and the AI will respond.

The bot is created through the special bot `@BotFather` — this is Telegram's official tool for managing bots.

1. Open Telegram and find `@BotFather` (with a blue verification checkmark)
2. Send it the command:

```
/newbot
```

3. BotFather will ask for the bot's name — this is the display name, for example `My AI Assistant`
4. Then it will ask for a username — this is the technical name, must end with `bot`, for example `my_ai_helper_bot`
5. BotFather will respond with a message containing the bot token — a string like `7123456789:AAF...`

The bot token is your bot's address and password in one string. Whoever holds the token — controls the bot. Save it as securely as the API key.

---

**Step 3. Connect the Telegram channel to OpenClaw**

Connect to the server via SSH (as done in previous phases) and run:

```bash
openclaw channels add --channel telegram --token 'YOUR_TELEGRAM_BOT_TOKEN'
```

Replace `YOUR_TELEGRAM_BOT_TOKEN` with the actual token received from BotFather (the string like `7123456789:AAF...`).

Next, configure the allowlist (a list of those permitted to communicate with the bot). This is important: without an allowlist, any Telegram user can message your bot and spend your API budget.

Verify that the channel was added:

```bash
openclaw channels list
```

Expected result:

```
Channel    Status     Bot Username
telegram   configured @my_ai_helper_bot
```

**Step 3.5. Disable link previews**

```bash
# Disable link previews — protection against data leakage
openclaw config set channels.telegram.linkPreview false
```

Why this is needed: a malicious web page can force the agent to generate a URL containing secret data (such as tokens or fragments of your conversation). The messenger will automatically load a preview of this URL, sending data to the attacker without your knowledge. Disabling previews blocks this attack vector — links will still be clickable, but their content will not be loaded automatically.

---

**Step 4. Configure the AI model and agent security**

Specify which AI model to use. For Claude Sonnet (recommended as a balance of quality and cost):

```bash
openclaw config set agents.defaults.model anthropic/claude-sonnet-4-6
```

Save the API key in the environment configuration:

```bash
openclaw config set env.ANTHROPIC_API_KEY "your-api-key"
```

Replace `your-api-key` with the actual key obtained in Step 1. Quotes are required.

If you chose OpenAI, use this instead:

```bash
openclaw config set agents.defaults.model openai/gpt-4o
openclaw config set env.OPENAI_API_KEY "your-api-key"
```

Enable full isolation — all agent tools will run inside a Docker container, with no access to the main system:

```bash
openclaw config set agents.defaults.sandbox.mode all
```

Set the minimal tool set — the agent will only be able to conduct a dialog, without access to files, browser, or command line:

```bash
openclaw config set agents.defaults.tools.profile minimal
```

---

**Step 5. Start the Gateway**

The Gateway — the central OpenClaw process that receives messages from Telegram, passes them to the AI, and returns responses. It must run continuously.

```bash
openclaw gateway restart
```

Expected result:

```
Gateway restarted successfully
Listening on 127.0.0.1:18789
Channels: telegram (connected)
```

---

**Step 6. Send your first message**

Open Telegram, find your bot by username (for example, `@my_ai_helper_bot`) and send:

```
Hello! Tell me about yourself.
```

Within a few seconds, the bot should respond with a message from the AI.

### Verification

1. Send the bot a message "Hello!" in Telegram — a response should arrive within 5-15 seconds

2. Check the system status:

```bash
openclaw status
```

Expected result — an active session, connected Telegram channel, model name.

3. Check the logs for errors:

```bash
openclaw logs
```

Expected result — entries about a received message, request sent to the AI, and response delivered, without lines containing `ERROR`.

### Common Issues

**"Bot does not respond, logs are silent"**

The bot token was entered incorrectly or the Gateway is not running. Check the token: `openclaw channels status`. Restart: `openclaw gateway restart`.

**"Unauthorized" or "401" in logs**

The API key is incorrect, expired, or not activated. Check the key in the provider's dashboard (console.anthropic.com or platform.openai.com). Make sure a payment method is linked.

**"Response takes 30+ seconds"**

Normal for the first message — the AI service is "warming up." Also depends on the provider's server load. Wait. Subsequent messages will be faster.

**"Rate limited" or "429" in logs**

You are sending too many messages in a short time. Each provider has a requests-per-minute limit. Wait a minute and try again. For new accounts, limits are lower.

**"Insufficient funds" or "402"**

The API account balance is exhausted. Top up the balance in the provider's dashboard.

**"Bot responds, but not to me"**

The allowlist is configured incorrectly, and someone else found your bot. Review the allowlist: `openclaw channels add --channel telegram --token 'YOUR_TOKEN'` (reconfigure).

### Links

- Creating bots in Telegram: https://core.telegram.org/bots#botfather
- Anthropic API documentation: https://docs.anthropic.com/en/api/getting-started
- OpenAI API documentation: https://platform.openai.com/docs/quickstart
- OpenClaw channel management: https://github.com/openclaw/openclaw (Channels section)

---

## Phase 5: Agent Team

### What We Are Doing and Why

In Phase 4, we launched a single universal agent. It can hold a conversation but cannot write code, work with files, or search the internet. Giving one agent all capabilities at once is a bad idea from a security standpoint: if the AI makes a mistake or is tricked by a specially crafted message (prompt injection — an attack through text that forces the AI to perform unwanted actions), it would have access to everything at once.

Imagine you have a team of assistants. Each one is a specialist in their field. One answers questions, another writes code, a third searches for information online. They all work on one server but are isolated from each other — like employees in separate offices with different access keys.

In this phase, we will configure three agents:

| Agent | Purpose | What it can do | What it CANNOT do |
|-------|---------|----------------|-------------------|
| **Assistant** | Everyday questions, conversation | Conversation only | Files, code, internet |
| **Coder** | Code, files, technical tasks | Read/write files, execute commands | Internet, browser |
| **Researcher** | Searching for information online | Browser (in isolation) | Files, command execution |

### Diagram

```
Telegram ──► OpenClaw Gateway
               │
               │  message ──► routing by command
               │
               ├── (default) ──────► Assistant (Claude, conversation only)
               │                        └── Sandbox A (isolated, no tools)
               │
               ├── /coder ──────────► Coder (GPT-4o, files + code)
               │                        └── Sandbox B (isolated, access to /workspaces/coder)
               │
               └── /research ───────► Researcher (Claude, browser)
                                        └── Sandbox C (isolated, no file access)

Each agent = separate Docker container + own API key + own permissions
```

### Steps

**Step 1. Create a workspace directory for the Coder**

A workspace directory is a folder on the server where the coder agent can save files. The agent will see only this folder and nothing beyond it.

```bash
sudo mkdir -p /opt/openclaw/workspaces/coder
sudo chown openclaw:openclaw /opt/openclaw/workspaces/coder
```

Expected result: the commands execute without errors. Verify:

```bash
ls -la /opt/openclaw/workspaces/
```

Expected result:

```
drwxr-xr-x 2 openclaw openclaw 4096 ... coder
```

---

**Step 2. Obtain additional API keys (if needed)**

If you want to use different AI providers for different agents (for example, Claude for the assistant and GPT-4o for the coder), you will need API keys from both services. Create them following the instructions from Phase 4, Step 1.

If you want to use one provider for all agents — a single key is sufficient. However, it is recommended to create separate keys for each agent: this allows you to track spending per agent separately and disable one key without affecting the others.

---

**Step 3. Save API keys in environment variables**

Environment variables are named values accessible to programs on the server. They are safer than writing keys directly in the configuration file because they will not end up in command history or configuration backups.

Open the environment file for OpenClaw:

```bash
sudo nano /etc/openclaw/env
```

Add lines with your keys (replace the values with real ones):

```
AGENT_ASSISTANT_ANTHROPIC_KEY=sk-ant-your-key-for-assistant
AGENT_CODER_OPENAI_KEY=sk-your-key-for-coder
AGENT_RESEARCHER_ANTHROPIC_KEY=sk-ant-your-key-for-researcher
```

Save the file (Ctrl+O, Enter, Ctrl+X) and restrict access to it:

```bash
sudo chmod 600 /etc/openclaw/env
sudo chown openclaw:openclaw /etc/openclaw/env
```

`chmod 600` means: only the file owner can read and edit it. No one else on the server will have access to the keys.

To have OpenClaw load these variables at startup, specify the file path in the systemd configuration:

```bash
sudo mkdir -p /etc/systemd/system/openclaw.service.d
sudo tee /etc/systemd/system/openclaw.service.d/env.conf << 'EOF'
[Service]
EnvironmentFile=/etc/openclaw/env
EOF
sudo systemctl daemon-reload
```

The `daemon-reload` command forces systemd to reread service configurations. After this, every time OpenClaw starts, the variables from the `/etc/openclaw/env` file will be automatically loaded.

---

#### Step 2.5. Security rules for credentials

Connecting OpenClaw to external services (GitHub, Slack, Google Workspace, calendar) creates so-called "Shadow AI" — an uncontrolled agent with inherited user permissions. If an agent is compromised through prompt injection, the attacker inherits **all** permissions of the connected services.

**Rules:**

1. **Only dedicated service accounts** — never use personal or work accounts to grant access to agents
2. **Minimal permissions** — GitHub: tokens with access only to specific repositories, read-only. Slack: only `channels:read` + `chat:write`, never admin rights. Google: `gmail.readonly`, not `mail.google.com`
3. **Short-lived tokens** — when possible, use tokens with a 5-minute lifespan (reduces theft risk by 92% according to Okta 2025)
4. **Any credentials that enter the AI model's context should be considered compromised** — rotate them immediately

---

**Step 4. Create a configuration with three agents**

Create the Gateway configuration file — this is the main file describing all agents, their permissions, and message routing.

> **Important:** In Phase 3, we created the `openclaw.json5` file with general security settings (binding to loopback, authorization token, sandbox mode). The `gateway.yaml` file complements it — here we describe specific agents, their models, and routing. Both files live in `~/.openclaw/` and work together: `openclaw.json5` sets global security rules, while `gateway.yaml` sets individual settings for each agent.

```bash
nano ~/.openclaw/gateway.yaml
```

Paste the following content in its entirety:

```yaml
# Main OpenClaw Gateway configuration file
# Describes all agents, their access permissions, and message routing

gateway:
  bind: loopback     # Gateway listens only on localhost (127.0.0.1)
  port: 18789
  auth:
    mode: token      # Access to Gateway only by token

# Agent settings
agents:

  # Default settings for all agents
  defaults:
    sandbox:
      mode: all          # All tools run inside Docker
      scope: dedicated   # Each agent — separate container
      docker: true
    tools:
      profile: minimal   # By default — minimal tools
    workspaceAccess: none # By default — no file access

  # Definition of each agent
  definitions:

    # Assistant — everyday questions, conversation
    # No tools, no file access
    assistant:
      model:
        provider: anthropic
        name: claude-sonnet-4-6
      tools:
        profile: minimal
      sandbox:
        mode: all
        scope: dedicated
        workspaceAccess: none
      credentials:
        anthropicApiKey: ${AGENT_ASSISTANT_ANTHROPIC_KEY}

    # Coder — code generation, working with files
    # Can read and write files, execute commands
    # BUT only in its workspace directory, without internet access
    coder:
      model:
        provider: openai
        name: gpt-4o
      tools:
        profile: coding
        allow: [file_read, file_write, shell_exec]
        deny: [browser, network_fetch]
      sandbox:
        mode: all
        scope: dedicated
        workspaceAccess: rw
        workspaceDir: /opt/openclaw/workspaces/coder
      credentials:
        openaiApiKey: ${AGENT_CODER_OPENAI_KEY}

    # Researcher — searching for information online
    # Can open web pages in an isolated browser
    # BUT cannot write files or execute commands
    researcher:
      model:
        provider: anthropic
        name: claude-sonnet-4-6
      tools:
        profile: minimal
        allow: [browser]
        deny: [file_write, shell_exec]
      sandbox:
        mode: all
        scope: dedicated
        workspaceAccess: none
      credentials:
        anthropicApiKey: ${AGENT_RESEARCHER_ANTHROPIC_KEY}

# Communication channels
channels:
  telegram:
    defaultAgent: assistant    # Regular messages go to the Assistant
    agentRouting:              # Commands for switching to other agents
      /coder: coder
      /research: researcher
```

Save the file (Ctrl+O, Enter, Ctrl+X).

**What is happening here:**

- `defaults` sets security rules that apply to all agents unless overridden for a specific agent
- Each agent in `definitions` describes: which AI model to use, which tools are allowed/denied, what level of file access
- `${AGENT_...}` — references to environment variables from Step 3. The Gateway will substitute the actual keys at startup
- `agentRouting` defines how to switch between agents in Telegram using commands

**Why security is configured this way:**

| Agent | Tools | Files | Internet | Rationale |
|-------|-------|-------|----------|-----------|
| Assistant | None | None | None | Minimal attack surface. If the AI is tricked through a message — it can do nothing but respond with text |
| Coder | Files, commands | Only `/workspaces/coder` | None | Can work with code, but only in the designated folder. Cannot access the internet — meaning it cannot send your data outward |
| Researcher | Browser | None | Yes (via sandbox) | Can search for information, but cannot save files to the server. The browser runs inside a Docker container, isolated from the main system |

> **Reader security:** An agent working with external content (web pages, documents) is the most vulnerable to "indirect prompt injection" attacks (when malicious instructions are hidden in web page or document content, and the AI executes them thinking they are part of the task). Therefore, the researcher agent is denied access to memory files and configuration — even if an attacker "tricks" it through a prepared page, the agent cannot modify system settings or other agents' data.

---

**Step 5. Protect agent identity files**

The `SOUL.md` and `MEMORY.md` files define the "personality" and "memory" of your agents — instructions by which the AI behaves in a certain way. A "memory poisoning" attack is when malicious content modifies these files, creating a persistent backdoor (a hidden entrance) that survives reboots and works unnoticed.

Protect these files from modification:

```bash
# Protect agent identity files from poisoning
sudo chattr +i ~/openclaw/workspace/SOUL.md
sudo chattr +i ~/openclaw/workspace/MEMORY.md
```

Now, to update the identity files, you need to explicitly remove the protection (`sudo chattr -i`), make changes, and restore the protection — exactly as we did with the SSH configuration in Phase 2.

---

**Step 5.5. Limit agent container resources**

Without limits, one "stuck" agent container can consume all the server's RAM and crash the system — including the Gateway and the other agents. It is like one tenant in an apartment building turning all faucets on full — there will not be enough water for the rest.

In the `gateway.yaml` file, update the `defaults` section under `sandbox` by adding resource limits:

```yaml
sandbox:
  mode: all
  scope: dedicated
  docker: true
  memory: "512m"
  cpus: "0.5"
```

The `memory: "512m"` parameter limits each agent container to 512 MB of memory, and `cpus: "0.5"` — to half of one CPU core.

Calculation for a VPS with 4 GB RAM: Gateway (1.5 GB) + 3 agents at 512 MB each (1.5 GB) + system (0.5 GB) = ~3.5 GB — fits within the limit with room to spare.

---

**Step 6. Apply the configuration**

Recreate sandbox containers (isolation environments) for the new agents and restart the Gateway:

```bash
openclaw sandbox recreate
openclaw gateway restart
```

Expected result for `sandbox recreate`:

```
Recreating sandboxes...
Created sandbox: assistant (dedicated)
Created sandbox: coder (dedicated)
Created sandbox: researcher (dedicated)
```

Expected result for `gateway restart`:

```
Gateway restarted successfully
Agents: assistant, coder, researcher
Channels: telegram (connected)
```

---

**Step 6. Test each agent**

Open Telegram and write to your bot.

*Testing the Assistant (works by default):*

Send:
```
What is the weather like on Mars right now?
```
Expected result: a text response with general knowledge, without an internet search.

*Testing the Coder:*

Send:
```
/coder
```
The bot will confirm switching to the Coder agent. Then send:
```
Write a Python script that calculates the factorial of 10
```
Expected result: the agent will write code and may execute it, showing the result.

*Testing the Researcher:*

Send:
```
/research
```
The bot will confirm the switch. Then send:
```
Find the latest news about SpaceX launches
```
Expected result: the agent will open a browser in an isolated container, find information, and send a summary.

To return to the Assistant, send any regular message (without the `/coder` or `/research` command), and the routing will return to the default agent.

### Verification

1. Send the bot a regular message — the Assistant responds (text only)

2. Send `/coder`, then a coding question — the Coder responds (can create files)

3. Send `/research`, then a search request — the Researcher uses the browser

4. Verify that three separate containers are running:

```bash
openclaw sandbox list
```

Expected result:

```
Agent        Sandbox    Status    Workspace Access
assistant    dedicated  running   none
coder        dedicated  running   rw (/opt/openclaw/workspaces/coder)
researcher   dedicated  running   none
```

5. Verify that access permissions are configured correctly:

```bash
openclaw sandbox explain
```

Expected result — a detailed table showing, for each agent, which tools are available, which files are visible, and whether there is internet access.

6. Verify that the Coder writes files only in its directory:

```bash
ls /opt/openclaw/workspaces/coder/
```

Files created by the Coder during testing should appear here.

7. Run the security audit:

```bash
openclaw security audit --deep
```

All checks should pass without errors (PASS). If there are warnings (WARN) or errors (FAIL) — read the description and fix them.

### Common Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| Agent does not switch with the `/coder` or `/research` command | Routing is not configured or the Gateway did not reload the configuration | Check the `agentRouting` section in `gateway.yaml`. Restart: `openclaw gateway restart` |
| Coder cannot write files, `Permission denied` error | The `/opt/openclaw/workspaces/coder` directory belongs to a different user | Fix ownership: `sudo chown openclaw:openclaw /opt/openclaw/workspaces/coder` |
| Researcher does not open web pages | Browser is not allowed in the sandbox configuration or Docker cannot launch a headless browser (a browser without a graphical interface, running in the background) | Check `allow: [browser]` in the configuration. Recreate the sandbox: `openclaw sandbox recreate` |
| The wrong agent responds to a question | `defaultAgent` is incorrectly specified or routing is confused | Check `defaultAgent: assistant` and the `agentRouting` section in `gateway.yaml` |
| `Error: credential not found` on startup | Environment variables are not loaded | Check the `/etc/openclaw/env` file and restart the service: `openclaw gateway restart` |
| One of the containers does not start | Docker lacks resources (memory or disk space) | Check: `docker ps -a` for container status, `df -h` for free space, `free -m` for memory |
| `security audit` shows FAIL | The configuration contains unsafe parameters | Run `openclaw security audit --fix` for automatic fixing of safe issues, fix the rest manually following the descriptions |

### Links

- OpenClaw multi-agent configuration: https://github.com/openclaw/openclaw (Multi-Agent section)
- Sandbox management: https://github.com/openclaw/openclaw (Sandboxing section)
- Tool policies: https://github.com/openclaw/openclaw (Tool Policies section)
- Security audit: https://github.com/openclaw/openclaw (Security Audit section)

---

## Phase 6: Maintenance and Monitoring

### What We Are Doing and Why

In the previous phases, we installed and configured OpenClaw on the VPS. But a server is not a household appliance that you can "set and forget." Without regular maintenance, security settings can "drift" (someone accidentally changes the config via chat), updates will not be installed, and API costs can spiral out of control.

In this phase, we will set up a simple maintenance routine: 5 minutes per week and 15 minutes per month — this is enough to keep the system secure and stable.

> **Tip:** If you used the automated installer, the optional `06-maintenance.sh` script can automate parts of this maintenance routine. Run `bash /opt/openclaw/scripts/06-maintenance.sh` to set up automated weekly checks and backups.

### Diagram

```
┌── Weekly (5 minutes) ────────────────────────────────┐
│                                                       │
│  security audit → git diff → cron list                │
│  → reboot check → token usage                        │
│                                                       │
├── Monthly (15 minutes) ──────────────────────────────┤
│                                                       │
│  openclaw update → apt upgrade                        │
│  → backup → spending review                          │
│                                                       │
├── As needed (on failures) ───────────────────────────┤
│                                                       │
│  logs → doctor → restart → config rollback            │
│                                                       │
└───────────────────────────────────────────────────────┘
```

### Steps

---

#### 1. Weekly Check (5 minutes)

This is your server "walk-through" — like a security guard patrolling a building. Five commands that give a complete picture of the system's state. Run them every week on a convenient day.

Connect to the server via SSH (as we did in the previous phases):

```bash
ssh openclaw@your-server
```

**Step 1.1. Security audit**

```bash
openclaw security audit --deep
```

This command runs more than 50 automatic checks: file access permissions, channel settings, container isolation, network connections. The `--deep` flag adds a live WebSocket connection check (a protocol for real-time data exchange between the gateway and clients).

Expected output — all checks passed:

```
Security Audit Results
━━━━━━━━━━━━━━━━━━━━━
✓ Gateway binding: loopback only
✓ Auth mode: token
✓ Sandbox mode: all
✓ Workspace access: none
...
52/52 checks passed
```

If any checks fail — the command will show what exactly is wrong and suggest a fix. You can apply safe fixes automatically:

```bash
openclaw security audit --fix
```

This command will fix only the issues that can be safely repaired automatically and will output the remaining list.

**Step 1.2. Check configuration changes**

```bash
cd ~/.openclaw && git diff
```

In Phase 3, we placed the `~/.openclaw` directory under version control (a change tracking system). The `git diff` command shows all changes since the last save. If you have not changed settings manually — the output should be empty.

Expected output when nothing has changed:

```
(empty output — no changes)
```

If you see unexpected changes — someone or something modified the configuration. This may be a sign of a problem. How to roll back is described in the "When something goes wrong" section below.

**Step 1.3. Check scheduled tasks**

```bash
openclaw cron list
```

Shows all scheduled tasks (cron jobs — automatically executed actions on a schedule). Make sure the list contains only tasks you created yourself. Unknown tasks may be a sign that an agent created them without your knowledge.

Expected output:

```
Scheduled Tasks
━━━━━━━━━━━━━━
ID    Schedule      Agent        Description
1     0 9 * * *     assistant    Morning news summary
```

If you see unfamiliar tasks — delete them:

```bash
openclaw cron rm <ID>
```

**Step 1.4. Check if a reboot is needed**

```bash
cat /var/run/reboot-required 2>/dev/null || echo "No reboot needed"
```

The automatic update system (configured in Phase 2) sometimes installs kernel updates (kernel — the operating system kernel, the deepest level of software). Such updates take effect only after a server reboot.

Expected output when no reboot is needed:

```
No reboot needed
```

If the file exists — the system will say:

```
*** System restart required ***
```

How to safely reboot the server is described in the "Server update" section below.

**Step 1.5. Check token usage**

```bash
openclaw status --all | grep -E "(requests|tokens|cost)"
```

Shows how many requests were sent to AI models, how many tokens (text units that providers use for billing) were consumed, and the approximate cost.

Expected output:

```
  requests: 847 (last 7 days)
  tokens:   1.2M input / 340K output
  cost:     ~$4.20 (estimated)
```

If usage is unexpectedly high — perhaps one of the agents is looping or receiving too many messages. Check the logs (described below).

---

#### 1.5. Daily Automatic Audit (configured once)

Instead of manually checking the server every day, we set up an automatic nightly audit — a script that checks key security metrics and writes a report to a log file. This is like video surveillance: recording runs around the clock, and you review it only if something happens. The approach is based on SlowMist security audit recommendations.

Create the script file:

```bash
sudo mkdir -p /opt/security
sudo nano /opt/security/nightly-audit.sh
```

Paste the content:

```bash
#!/bin/bash
# /opt/security/nightly-audit.sh
# Nightly security audit

REPORT="/var/log/security-audit/$(date +%Y-%m-%d).log"
mkdir -p /var/log/security-audit

echo "=== Audit $(date) ===" > "$REPORT"

# 1. New open ports
ss -tlnp >> "$REPORT"

# 2. Changes in /etc
cd /opt/security/baselines 2>/dev/null && \
  find /etc -type f -exec sha256sum {} + 2>/dev/null | \
  diff etc_hashes.baseline - >> "$REPORT" 2>/dev/null

# 3. OpenClaw security check
openclaw security audit --deep >> "$REPORT" 2>/dev/null

# 4. Configuration check
cd ~/.openclaw && git diff >> "$REPORT"

# 5. Gateway memory usage
ps -o rss=,vsz=,pid=,comm= -C node >> "$REPORT"

echo "=== Completed ===" >> "$REPORT"
```

Install the script and add it to the cron schedule (task scheduler — a program that automatically runs commands on a schedule, like an alarm clock for scripts):

```bash
sudo chmod 700 /opt/security/nightly-audit.sh
echo "0 3 * * * root /opt/security/nightly-audit.sh" | sudo tee /etc/cron.d/security-audit
```

The script will run every night at 3:00 AM and write the report to `/var/log/security-audit/`. View reports with:

```bash
cat /var/log/security-audit/$(date +%Y-%m-%d).log
```

---

#### 1.6. Skills Security

Skills are additional capabilities that can be installed from the ClawHub catalog (like apps from a store).

In January-February 2026, a massive supply chain attack on ClawHub occurred, dubbed **ClawHavoc** — more than 800 malicious skills (about 20% of the entire catalog) contained trojans (programs disguised as useful ones), keyloggers (keystroke interceptors), and stealers (programs for stealing passwords and tokens). Many of these skills were exact copies of popular ones, with minimal changes in the name.

Security rules when working with skills:

1. Never install skills without a prior source code audit — review the skill's files on GitHub before installation
2. Pin versions: `clawhub install <skill> --version X.Y.Z` — this ensures the skill does not auto-update to a malicious version
3. Do not execute commands from the "Prerequisites" section in SKILL.md — malicious skills often ask to run dangerous commands under the guise of "installation preparation"
4. Use ClawVet to scan skills before installation: `github.com/MohibShaikh/clawvet`

**Automatic skill scanning**

Manual auditing is useful but insufficient at the scale of the ClawHavoc campaign (800+ malicious skills). Use automatic scanners:

| Tool | What it does | Installation |
|------|-------------|-------------|
| Cisco AI Skill Scanner | Static + semantic analysis + VirusTotal | `pip install cisco-ai-skill-scanner` |
| Aguara | 177 detection rules, no API keys required | github.com/garagon/aguara |

Example of scanning before installing a skill:

```bash
skill-scanner scan /path/to/skill --policy strict
```

If the scanner finds issues at the `high` or `critical` level — do not install the skill.

---

#### 2. Updating OpenClaw

OpenClaw updates are released regularly and contain security fixes, new features, and performance improvements. Recommended frequency — once a month.

**Step 2.1. Check what is new in the update**

Before updating, it is always useful to see what has changed. The changelog is published on the project page:

```
https://github.com/openclaw/openclaw/releases
```

Open this page in a browser and read the description of the latest version. Pay attention to the "Breaking Changes" sections (critical changes that may require action on your part) — if they exist.

**Step 2.2. Save the current configuration**

Before any update, take a configuration snapshot — if something goes wrong, you can revert:

```bash
cd ~/.openclaw && git add . && git commit -m "before update $(date +%Y-%m-%d)"
```

Expected output:

```
[master abc1234] before update 2026-03-15
 1 file changed, 0 insertions(+), 0 deletions(-)
```

If the output says "nothing to commit" — the configuration has not changed since the last save, and that is normal.

**Step 2.3. Perform the update**

```bash
openclaw update
```

The command will download and install the latest version of OpenClaw. The Gateway will restart automatically.

Expected output:

```
Updating OpenClaw...
Current version: v2026.3.7
Latest version:  v2026.4.1
Downloading... done
Installing... done
Restarting gateway... done
Updated to v2026.4.1
```

**Step 2.4. Verify everything works after the update**

```bash
openclaw doctor
```

Expected output — all checks passed:

```
OpenClaw Doctor
━━━━━━━━━━━━━━
✓ Node.js version: 22.x
✓ Docker: running
✓ Gateway: healthy
✓ Channels: connected
✓ Sandbox: operational
All checks passed
```

---

#### 3. Cost Monitoring

AI models are billed by the number of tokens — the more text you send and receive, the more expensive it gets. Without cost control, expenses can be unpleasantly surprising at the end of the month.

**Step 3.1. Checking costs on the provider side**

The `openclaw status` data is an estimate. For exact numbers, check the providers' dashboards:

- **Anthropic (Claude):** https://console.anthropic.com — "Usage" section
- **OpenAI (GPT):** https://platform.openai.com/usage — "Usage" section

Visit these at least once a month.

**Step 3.2. Setting spending limits**

Be sure to set spending limits with each provider — this is insurance against unexpected costs:

- **Anthropic:** https://console.anthropic.com → Settings → Spending Limits
- **OpenAI:** https://platform.openai.com/settings → Billing → Usage limits

Recommended initial limits for personal use: $10-20 per month per provider. Adjust later based on actual usage.

**Step 3.3. Why separate API keys for each agent**

In Phase 4, we configured a separate API key for each agent. This is not only a security measure — it is also a cost control tool. If each agent has its own key, you can see in the provider's dashboard exactly how much each agent is spending. And if one agent goes out of control, you can disable only its key without affecting the others.

**Step 3.4. Approximate monthly costs**

Estimated costs for typical personal use (10-30 messages per day):

| Scenario | Model | Approximate monthly cost |
|----------|-------|--------------------------|
| Light usage (10 messages/day, short dialogs) | Claude Sonnet | $3-7 |
| Medium usage (20-30 messages/day, medium dialogs) | Claude Sonnet | $8-15 |
| Heavy usage (50+ messages/day, long dialogs with documents) | Claude Sonnet | $20-40 |
| Using GPT-4o instead of Claude | GPT-4o | Roughly the same range |

The VPS server cost (about $5-10/mo) is added on top. Total typical budget: **$15-25 per month** for a fully private personal AI assistant.

---

#### 4. Backup

If the server goes down, you will need to restore the configuration. Everything important is stored in one directory: `~/.openclaw/`.

**Step 4.1. What needs to be backed up**

The `~/.openclaw/` directory contains:
- `openclaw.json` — the main configuration file
- Channel keys and tokens (Telegram, WhatsApp)
- Agent settings
- Session history

This directory is already under git version control (we set this up in Phase 3), so you have a history of all changes on the server itself. But if the server disappears — so does this history. That is why you need a copy on your computer.

**Step 4.2. Copy to your computer**

Run this command **on your local computer** (not on the server):

```bash
scp -r openclaw@your-server:~/.openclaw/ ~/openclaw-backup-$(date +%Y-%m-%d)/
```

The `scp` command (Secure Copy) downloads the entire `~/.openclaw/` directory from the server to a folder on your computer with the date in the name.

Expected output:

```
openclaw.json                     100%  2.1KB   125.3KB/s   00:00
...
```

**Step 4.3. Simple script for regular backups**

To avoid typing the command manually each time, create a script file on your computer (a set of commands that can be run with a single action):

```bash
#!/bin/bash
BACKUP_DIR="$HOME/openclaw-backups"
DATE=$(date +%Y-%m-%d)
mkdir -p "$BACKUP_DIR"
scp -r openclaw@your-server:~/.openclaw/ "$BACKUP_DIR/backup-$DATE/"
echo "Backup saved to $BACKUP_DIR/backup-$DATE/"

# Delete backups older than 90 days
find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup-*" -mtime +90 -exec rm -rf {} +
```

Save it as `~/openclaw-backup.sh` and make it executable:

```bash
chmod +x ~/openclaw-backup.sh
```

Run it once a month:

```bash
~/openclaw-backup.sh
```

Expected output:

```
Backup saved to /home/yourname/openclaw-backups/backup-2026-03-15/
```

**Step 4.4. Automatic agent memory backup**

In addition to a full configuration copy, you need to separately save the agents' "brain" — memory files. If an agent's memory is poisoned (through a memory poisoning attack), you can roll it back to a clean version from the backup.

Create a script:

```bash
sudo nano /opt/security/agent-brain-backup.sh
```

Paste the content:

```bash
#!/bin/bash
# /opt/security/agent-brain-backup.sh
BACKUP_DIR="/opt/backups/openclaw-brain"
AGENT_DIR="$HOME/.openclaw"
mkdir -p "$BACKUP_DIR"

cd "$BACKUP_DIR"
[ -d .git ] || git init

cp -r "$AGENT_DIR/memory/" "$BACKUP_DIR/memory/" 2>/dev/null
cp "$AGENT_DIR/openclaw.json" "$BACKUP_DIR/" 2>/dev/null

git add -A
git diff --cached --quiet || git commit -m "backup $(date +%Y-%m-%d_%H%M)"
```

Install the script and add it to the schedule (every hour):

```bash
sudo chmod 700 /opt/security/agent-brain-backup.sh
echo "0 * * * * openclaw /opt/security/agent-brain-backup.sh" | sudo tee /etc/cron.d/agent-backup
```

If you need to restore agent memory (for example, after detecting suspicious behavior):

```bash
cd /opt/backups/openclaw-brain
git log --oneline -10
git checkout <commit> -- memory/
cp -r memory/ ~/.openclaw/memory/
openclaw gateway restart
```

Replace `<commit>` with the hash of the needed commit from the list — for example, the last "clean" snapshot before the agent started behaving strangely.

---

#### 5. Server Update

The server's operating system also needs updates. Automatic security updates are installed in Phase 2 (the `unattended-upgrades` package), but a full update of all packages is best done manually once a month.

**Step 5.1. Update the package list and install updates**

```bash
sudo apt update && sudo apt upgrade -y
```

The first part (`apt update`) downloads a fresh list of available packages. The second (`apt upgrade -y`) installs all updates. The `-y` flag means automatic agreement to install.

Expected output:

```
Reading package lists... Done
Building dependency tree... Done
The following packages will be upgraded:
  libssl3 openssl ...
3 upgraded, 0 newly installed, 0 to remove.
...
```

**Step 5.2. Check if a reboot is needed**

```bash
cat /var/run/reboot-required 2>/dev/null || echo "No reboot needed"
```

If a reboot is needed (usually after a kernel update), proceed to the next step.

**Step 5.3. Safe server reboot**

Before rebooting, make sure OpenClaw is installed as a system service (daemon — a background process that automatically starts on system boot). We did this in Phase 3 with the `openclaw service install` command. In this case, after reboot, OpenClaw will start on its own.

Verify that the service is set to auto-start:

```bash
systemctl is-enabled openclaw
```

Expected output:

```
enabled
```

If the output is `enabled` — it is safe to reboot:

```bash
sudo reboot
```

The server will be unavailable for 1-2 minutes. After rebooting, connect again and check:

```bash
ssh openclaw@your-server
systemctl status openclaw
```

Expected output:

```
● openclaw.service - OpenClaw Gateway
     Loaded: loaded (/etc/systemd/system/openclaw.service; enabled)
     Active: active (running) since ...
```

The status `active (running)` means the gateway started automatically after reboot. Your channels (Telegram, WhatsApp) will reconnect on their own within a few seconds.

---

#### 6. When Something Goes Wrong

If OpenClaw stops responding to messages, works with errors, or behaves strangely — here is the diagnostic order, from simple to complex.

**Step 6.1. Check the service status**

```bash
systemctl status openclaw
```

If the status is `active (running)` — the service is running, the problem is elsewhere. If `inactive` or `failed` — the service has crashed.

**Step 6.2. Read the logs**

```bash
openclaw logs
```

Logs (event journal — records of all system actions) will show the latest events. Look for lines with `ERROR` or `WARN` — they indicate problems.

To see only errors:

```bash
openclaw logs | grep -i error
```

Common errors and their meanings:

| Error in logs | What it means | What to do |
|---------------|--------------|-----------|
| `ANTHROPIC_API_KEY invalid` | Invalid or revoked API key | Update the key in the configuration |
| `rate limit exceeded` | Provider request limit exceeded | Wait or increase the limit with the provider |
| `channel disconnected` | Lost connection to Telegram/WhatsApp | Restart the gateway (step 6.4) |
| `sandbox: docker not running` | Docker is not running | `sudo systemctl start docker` |
| `ENOSPC` | Disk space exhausted | Free up space: `sudo apt autoremove && sudo docker system prune` |

**Step 6.3. Automatic diagnostics**

```bash
openclaw doctor
```

The command checks all system components: Node.js version, Docker, gateway state, channel connections, sandbox operation. If something is wrong — it will show the problem and suggest a solution.

**Step 6.4. Restart the gateway**

If the problem is not resolved — restart the gateway:

```bash
openclaw gateway restart
```

Expected output:

```
Stopping gateway... done
Starting gateway... done
Gateway is running
```

The restart takes a few seconds. Channels will reconnect automatically.

If `openclaw gateway restart` does not help, try via systemd:

```bash
sudo systemctl restart openclaw
```

**Step 6.5. Check the service status**

```bash
systemctl status openclaw
```

Make sure the status is `active (running)` and there are no errors in the last lines of the output.

**Step 6.6. Configuration rollback (last resort)**

If the problem appeared after changing settings and you cannot figure out what exactly broke — revert the configuration to the last working state:

```bash
cd ~/.openclaw && git checkout .
```

This command will undo all configuration changes made after the last `git commit`. Then restart the gateway:

```bash
openclaw gateway restart
```

If you need to roll back to a specific save — view the history:

```bash
cd ~/.openclaw && git log --oneline
```

Expected output:

```
abc1234 before update 2026-03-15
def5678 before update 2026-02-15
789abcd baseline hardened config
```

Roll back to the desired point:

```bash
cd ~/.openclaw && git checkout <commit-hash> -- .
openclaw gateway restart
```

Replace `<commit-hash>` with the needed identifier from the list (for example, `789abcd`).

---

### Verification

Run the full weekly check cycle and make sure each command gives the expected result:

```bash
openclaw security audit --deep
```
Expected result: all checks passed, no warnings.

```bash
cd ~/.openclaw && git diff
```
Expected result: empty output (no unexpected changes).

```bash
openclaw cron list
```
Expected result: only tasks you recognize.

```bash
cat /var/run/reboot-required 2>/dev/null || echo "No reboot needed"
```
Expected result: "No reboot needed" or a notification that you handle per the instructions above.

```bash
openclaw status --all | grep -E "(requests|tokens|cost)"
```
Expected result: numbers matching your usage volume.

```bash
openclaw doctor
```
Expected result: all checks passed.

### Post-Installation Security Checklist

Go through each item after completing all phases. Each one is the result of a specific step described above:

- [ ] OpenClaw version is no lower than v2026.3.12
- [ ] Authorization token generated and saved
- [ ] `~/.openclaw/` has permissions 700
- [ ] NODE_OPTIONS includes --max-old-space-size=1536
- [ ] systemd has MemoryHigh and MemoryMax limits
- [ ] Link previews disabled in the Telegram channel
- [ ] SOUL.md and MEMORY.md files protected via chattr +i
- [ ] Agent containers have memory and CPU limits
- [ ] Nightly security audit configured via cron
- [ ] Agent memory backup configured
- [ ] `openclaw security audit --deep` passes without errors
- [ ] `session.dmScope` set to `per-channel-peer`
- [ ] Tools in group chats restricted (deny: exec, write, browser, gateway)
- [ ] External services connected through dedicated service accounts with minimal permissions
- [ ] Authorization token is 256 bits (`openssl rand -hex 32`)

### Common Issues

**Issue:** `openclaw security audit` shows warnings that were not there before.

Cause: the configuration has changed — possibly after an OpenClaw update added new checks, or someone changed the settings.

Solution:
```bash
openclaw security audit --fix
cd ~/.openclaw && git diff
```
Review what changed, and if the changes are correct — save:
```bash
cd ~/.openclaw && git add . && git commit -m "post-audit fix $(date +%Y-%m-%d)"
```

---

**Issue:** `git diff` shows changes you did not make.

Cause: an agent or an update changed the configuration.

Solution: carefully read what exactly changed. If the changes are unwanted:
```bash
cd ~/.openclaw && git checkout .
openclaw gateway restart
```

---

**Issue:** after `sudo reboot` the server does not respond for more than 5 minutes.

Cause: a problem with OS boot or the network.

Solution: go to the control panel of your VPS provider (Hetzner, DigitalOcean, etc.) and use the web console (a virtual server monitor accessible via the browser). It will show at which stage the server got stuck during boot.

---

**Issue:** `openclaw update` fails with an error.

Cause: a network problem or dependency conflict.

Solution:
```bash
openclaw doctor
sudo apt update && sudo apt upgrade -y
openclaw update
```
If that does not help — check whether there is enough disk space:
```bash
df -h /
```
There should be at least 2 GB of free space.

---

**Issue:** channels (Telegram/WhatsApp) disconnected after reboot.

Cause: usually channels reconnect automatically within 10-30 seconds. If more than a minute has passed — the session may have expired.

Solution:
```bash
openclaw channels status
```
If the channel shows status `disconnected`:
```bash
openclaw channels login <channel-name>
```
For WhatsApp, you will need to re-scan the QR code.

---

**Issue:** token usage is anomalously high.

Cause: a looping agent, spam in the channel, or dialog contexts that are too long.

Solution:
```bash
openclaw logs | grep -i "tokens"
openclaw status --all
```
Check which agent is consuming the most. If necessary, temporarily disable the problematic channel:
```bash
openclaw channels remove <channel-name>
```

### Links

- OpenClaw security documentation: https://docs.openclaw.ai/security
- `openclaw security audit` command: https://docs.openclaw.ai/cli/security-audit
- `openclaw doctor` command: https://docs.openclaw.ai/cli/doctor
- Update management: https://docs.openclaw.ai/updates
- Monitoring guide: https://docs.openclaw.ai/monitoring

---

## What's Next?

Congratulations — you have a fully configured, secured personal AI assistant running on your own server. Your data is under your control, the system is protected by five layers of security, and maintenance takes 5 minutes per week.

Here is what you can do next once you are comfortable with the basic setup:

**Add a WhatsApp channel**

If you only configured Telegram, add WhatsApp — a single gateway can serve multiple messengers simultaneously:

```bash
openclaw channels add whatsapp
```

The command will walk you through the linking process — you will need to scan a QR code with your phone.

**Set up automated tasks**

Schedule recurring tasks that the agent will perform on its own. For example, a daily news summary at 9 AM:

```bash
openclaw cron add --schedule "0 9 * * *" --agent assistant --prompt "Prepare a brief summary of yesterday's top news"
```

Other ideas: reminders, spending reports, monitoring web pages for changes.

**Try different AI models**

OpenClaw supports models from different providers. Try creating a second agent with a different model and compare response quality:

- Claude Sonnet — a good balance of speed and quality
- Claude Opus — maximum quality for complex tasks
- GPT-4o — an alternative from OpenAI
- Open-source models via compatible APIs

**Explore additional agent roles**

In Phase 4, we configured basic agents. As needed, you can add:

- **scheduler** — schedule management and reminders
- **notifier** — sending notifications on events
- **researcher** — searching for information online (in an isolated browser)
- **coder** — programming assistance (with file system access in a sandbox)

**Consider alternative architectures**

If your security requirements grow — for example, for working with financial data or in regulated industries — consider alternatives:

- **IronClaw** (github.com/nearai/ironclaw) — a Rust rewrite of OpenClaw with WebAssembly sandboxes (WASM — a compact virtual machine with zero default permissions) and certified cryptography (FIPS 140-3). Each skill runs in an isolated WASM environment and must explicitly request every permission
- **DigitalOcean App Platform** — a managed platform with out-of-the-box container isolation, automatic scaling, and predictable pricing. Suitable if you do not want to handle server administration

**Join the community**

- Official documentation: https://docs.openclaw.ai
- Source code on GitHub: https://github.com/openclaw/openclaw
- Discussions and questions: https://github.com/openclaw/openclaw/discussions
- Community guides collection: https://github.com/xianyu110/awesome-openclaw-tutorial
