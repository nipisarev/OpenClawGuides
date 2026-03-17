# OpenClaw Guides

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Ubuntu%2022.04-orange.svg)](https://ubuntu.com/)
[![shellcheck](https://img.shields.io/badge/shellcheck-passing-brightgreen.svg)](https://www.shellcheck.net/)

Deployment scripts and step-by-step guides for setting up a hardened OpenClaw AI agent server on Ubuntu/Debian VPS.

---

## What is this?

This repo provides battle-tested scripts and step-by-step guides for deploying OpenClaw on a hardened VPS. A single install command gets you from a bare server to a fully operational AI agent. Full security hardening with a 5-layer defense model is applied by default.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/nipisarev/OpenClawGuides/main/src/install.sh | bash
```

> If installation fails during Phase 2 (security hardening), the script automatically rolls back changes to prevent lockout. Keep your SSH session open during this phase.

## Features

- Automated server hardening (UFW, Fail2ban, SSH lockdown, chattr)
- Automatic rollback on failure -- SSH, UFW, and config changes are reverted if setup fails mid-way
- Pre-validation before locking -- sshd_config and SSH keys validated before chattr immutability
- Tailscale VPN mesh networking
- Node.js 22 + Docker + OpenClaw installation
- Telegram bot integration
- Multi-agent setup with gateway routing
- Nightly security audit (13 metrics)
- Automated brain backup with git
- systemd service with resource limits
- Credential persistence across re-runs
- Default model: claude-sonnet-4-6
- Correct OpenClaw CLI integration (channels add --channel, config env section)

## Security

Five layers of defense are applied during installation:

| Layer | Area | Controls |
|-------|------|----------|
| 1 | Network | UFW firewall + Tailscale VPN |
| 2 | Access | SSH key-only auth + Fail2ban |
| 3 | System | Unattended upgrades + chattr immutable configs |
| 4 | Application | Session isolation + resource limits |
| 5 | Monitoring | Nightly audit cron (13 checks) + Telegram alerts |

### Safety Mechanisms

- Trap handler auto-rollback: reverts UFW rules, SSH config, and chattr locks on script failure
- Timestamped config backups with automatic rotation (keeps last 3)
- SSH connectivity verification before and after dangerous operations
- UFW rule verification after enable -- auto-disables firewall if SSH rule is lost
- Guides include mandatory stop points for manual verification

## Guides

- [English setup guide](docs/guides/openclaw-setup-guide-en.md)
- [Russian setup guide](docs/guides/openclaw-setup-guide-ru.md)

## Security: Vulnerabilities & Mitigations

### Network attacks

| Vulnerability | Mitigation |
|---|---|
| Open ports / service exposure | UFW default-deny incoming; only SSH (22/tcp) + Tailscale (41641/udp) allowed |
| Gateway accessible from internet | Binds to 127.0.0.1 only (loopback); Tailscale mesh for remote access |
| Man-in-the-middle | Tailscale WireGuard encryption for all remote traffic |
| DNS/network sniffing | mDNS gateway discovery disabled |

### Access control

| Vulnerability | Mitigation |
|---|---|
| SSH brute force | Fail2ban: 5 attempts → 1h ban; key-only auth; root login disabled |
| Password-based SSH | PasswordAuthentication + ChallengeResponseAuthentication disabled |
| Unauthorized gateway access | 32-byte random auth token (`openssl rand -hex 32`) |
| SSH config tampering | `chattr +i` on sshd_config + root authorized_keys (immutable) |

### Application / AI agent risks

| Vulnerability | Mitigation |
|---|---|
| Agent filesystem escape | `sandbox.mode=all` → Docker isolation; `workspaceAccess=none` |
| Agent resource exhaustion | Memory 512M + CPU 0.5 per agent; systemd `MemoryMax=2G` |
| Cross-user session leakage | `session.dmScope=per-channel-peer` (isolated sessions) |
| Malicious plugins/skills | `autoInstall=false`; `trustedPublishers` empty; skills auto-install off |
| Chat-based config manipulation | `/config` command disabled in chat |
| Prompt injection via group chats | `groupPolicy=allowlist`; group tools restricted to read+message only |
| Link preview data exfiltration | Telegram `linkPreview` disabled |
| Log credential leakage | Logging redaction `mode="tools"` strips sensitive data |
| Browser sandbox escape | `evaluateEnabled=false` |
| Credential loss on config reshuffle | Backup file (`.credentials.env`, 600 perms) survives `doctor --fix` |

### System integrity

| Vulnerability | Mitigation |
|---|---|
| Unpatched OS vulnerabilities | `unattended-upgrades` enabled |
| Privilege escalation via systemd | `NoNewPrivileges=true`; `ProtectSystem=strict`; `PrivateTmp` |
| Unauthorized SUID, ports, crons | Nightly 13-metric audit with baseline drift detection |

---

### Sandbox Network Access

> **Note on sandbox networking:** By default, sandbox containers run with `network: none` (no internet access). If your agents need to fetch external data (e.g., morning briefing cron fetching weather/news), you must enable networking:
> ```bash
> openclaw config set agents.defaults.sandbox.docker.network bridge
> ```
> **Security impact:** This allows sandboxed agents to make outbound HTTP/HTTPS requests. While agents remain Docker-isolated (no filesystem/host access), they CAN reach external services. For maximum lockdown, keep `network: none` and only enable `bridge` if your use case requires it.

## Contributing

Issues and pull requests are welcome. Please open an issue to discuss larger changes before submitting a PR.

## License

[MIT](LICENSE)
