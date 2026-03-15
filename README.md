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

## Features

- Automated server hardening (UFW, Fail2ban, SSH lockdown, chattr)
- Tailscale VPN mesh networking
- Node.js 22 + Docker + OpenClaw installation
- Telegram bot integration
- Multi-agent setup with gateway routing
- Nightly security audit (13 metrics)
- Automated brain backup with git
- systemd service with resource limits

## Security

Five layers of defense are applied during installation:

| Layer | Area | Controls |
|-------|------|----------|
| 1 | Network | UFW firewall + Tailscale VPN |
| 2 | Access | SSH key-only auth + Fail2ban |
| 3 | System | Unattended upgrades + chattr immutable configs |
| 4 | Application | Session isolation + resource limits |
| 5 | Monitoring | Nightly audit cron (13 checks) + Telegram alerts |

## Guides

- [English setup guide](docs/guides/openclaw-setup-guide-en.md)
- [Russian setup guide](docs/guides/openclaw-setup-guide-ru.md)

## Project Structure

```
.
├── src/
│   ├── install.sh              # Main installer
│   ├── configs/                # Config templates (UFW, sshd, systemd, etc.)
│   ├── scripts/                # Hardening, audit, and backup scripts
│   └── tests/                  # Validation and smoke tests
├── docs/
│   └── guides/                 # Step-by-step setup guides
├── Makefile                    # Dev targets: install, test, lint, validate
├── LICENSE
└── README.md
```

## Contributing

Issues and pull requests are welcome. Please open an issue to discuss larger changes before submitting a PR.

## License

[MIT](LICENSE)
