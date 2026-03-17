#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# OpenClaw Hardened VPS Installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/nipisarev/OpenClawGuides/main/src/install.sh | bash
#
# This is the main entry point that:
#   1. Detects the OS (Ubuntu 22.04+ or Debian 12+)
#   2. Prints a welcome banner
#   3. Collects required information (Tailscale key, AI provider, API key, bot token)
#   4. Downloads the repo to /opt/openclaw-guides
#   5. Runs Phases 01-04 sequentially
#   6. Shows a final summary with Tailscale IP and next steps
#
# Run as root on a fresh server.
# ──────────────────────────────────────────────────────────────────────────────

# ── Inline colors & logging (before common.sh is available) ──────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

source "$(dirname "$0")/scripts/common.sh" 2>/dev/null || true

run_phase() {
    local phase_num="$1"
    local phase_name="$2"
    local phase_script="$3"

    log_info "Starting Phase $phase_num: $phase_name"

    if ! bash "$phase_script"; then
        log_error "Phase $phase_num ($phase_name) failed!"
        if [[ "$phase_num" == "2" ]]; then
            log_error "CRITICAL: Phase 2 failure may affect SSH access"
            log_error "Verify you can still SSH into the server before taking any action"
            log_error "If locked out, use your VPS provider's web console"
        fi
        log_error "Fix the issue and re-run: bash $phase_script"
        return 1
    fi

    log_success "Phase $phase_num ($phase_name) completed"
}

TOTAL_PHASES=4
INSTALL_DIR="/opt/openclaw-guides"
SCRIPTS_DIR="${INSTALL_DIR}/src/scripts"
REPO_URL="https://github.com/nipisarev/OpenClawGuides.git"

# ── Preflight checks ────────────────────────────────────────────────────────

# Must be root
if [[ $EUID -ne 0 ]]; then
    log_error "This installer must be run as root."
    echo -e "  Run: ${BOLD}sudo bash${NC} or ${BOLD}sudo su -${NC} first."
    exit 1
fi

# Detect OS
if [[ ! -f /etc/os-release ]]; then
    log_error "Cannot detect OS. Only Ubuntu 22.04+ and Debian 12+ are supported."
    exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

OS_ID="${ID:-unknown}"
OS_VERSION_ID="${VERSION_ID:-0}"
OS_CODENAME="${VERSION_CODENAME:-unknown}"

case "$OS_ID" in
    ubuntu)
        if [[ "${OS_VERSION_ID%%.*}" -lt 22 ]]; then
            log_error "Ubuntu ${OS_VERSION_ID} is not supported. Minimum: 22.04."
            exit 1
        fi
        ;;
    debian)
        if [[ "${OS_VERSION_ID%%.*}" -lt 12 ]]; then
            log_error "Debian ${OS_VERSION_ID} is not supported. Minimum: 12."
            exit 1
        fi
        ;;
    *)
        log_error "Unsupported OS: ${OS_ID}. Only Ubuntu 22.04+ and Debian 12+ are supported."
        exit 1
        ;;
esac

# ── Welcome banner ───────────────────────────────────────────────────────────

clear 2>/dev/null || true
echo -e "${BOLD}${BLUE}"
cat << 'BANNER'

   ___                    ____ _
  / _ \ _ __   ___ _ __  / ___| | __ ___      __
 | | | | '_ \ / _ \ '_ \| |   | |/ _` \ \ /\ / /
 | |_| | |_) |  __/ | | | |___| | (_| |\ V  V /
  \___/| .__/ \___|_| |_|\____|_|\__,_| \_/\_/
       |_|

BANNER
echo -e "${NC}"
echo -e "  ${BOLD}Hardened VPS Installer${NC} — Self-hosted AI Assistant"
echo ""
echo -e "  OS detected: ${BOLD}${OS_ID} ${OS_VERSION_ID}${NC} (${OS_CODENAME})"
echo ""
echo -e "  This installer will:"
echo -e "    1. Set up your server (user, packages, timezone)"
echo -e "    2. Harden security (firewall, fail2ban, SSH, VPN)"
echo -e "    3. Install OpenClaw (Node.js, Docker, config)"
echo -e "    4. Configure your first AI agent (Telegram bot)"
echo ""
echo -e "  Estimated time: ${BOLD}15-25 minutes${NC}"
echo ""
echo -e "  ${YELLOW}You will need:${NC}"
echo -e "    - Tailscale auth key (get at https://login.tailscale.com/admin/settings/keys)"
echo -e "    - AI provider API key (Anthropic or OpenAI)"
echo -e "    - Telegram bot token (from @BotFather)"
echo ""

# ── Detect existing installation ─────────────────────────────────────────────

ALREADY_INSTALLED=false
if id openclaw &>/dev/null; then
    OPENCLAW_HOME=$(eval echo "~openclaw")
    if [[ -f "${OPENCLAW_HOME}/.openclaw/openclaw.json5" ]]; then
        # Search for openclaw binary in known locations
        OC_FOUND=""
        for candidate in \
            "${OPENCLAW_HOME}/.local/share/pnpm/openclaw" \
            "/usr/local/bin/openclaw" \
            "/usr/bin/openclaw" \
            "${OPENCLAW_HOME}/.local/bin/openclaw"; do
            if [[ -f "$candidate" || -L "$candidate" ]]; then
                OC_FOUND="$candidate"
                break
            fi
        done
        # Fallback: search pnpm store
        if [[ -z "$OC_FOUND" ]]; then
            OC_FOUND=$(find "${OPENCLAW_HOME}/.local/share/pnpm" -name "openclaw" -type f 2>/dev/null | head -1)
        fi
        if [[ -n "$OC_FOUND" ]]; then
            ALREADY_INSTALLED=true
        fi
    fi
fi

if [[ "$ALREADY_INSTALLED" == true ]]; then
    echo -e "  ${GREEN}Existing installation detected.${NC} Running in update/repair mode."
    echo -e "  Skipping credential collection — using existing configuration."
    echo ""

    # Set empty credentials — phase scripts will skip prompts when services are already configured
    TAILSCALE_AUTH_KEY=""
    AI_PROVIDER=""
    AI_MODEL=""
    KEY_NAME=""
    API_KEY=""
    TELEGRAM_TOKEN=""
else
    # ── Collect information (first install only) ─────────────────────────────

    read -rp "$(echo -e "${YELLOW}?${NC} Press Enter to start, or Ctrl+C to cancel... ")" < /dev/tty
    echo ""

    # Tailscale auth key
    echo -e "${BOLD}Tailscale VPN${NC}"
    echo -e "  Create an auth key at: ${BLUE}https://login.tailscale.com/admin/settings/keys${NC}"
    echo -e "  (Click 'Generate auth key', copy the tskey-auth-... value)"
    echo ""
    read -rp "$(echo -e "${BLUE}?${NC} Tailscale auth key (tskey-auth-...): ")" TAILSCALE_AUTH_KEY < /dev/tty
    echo ""

    # AI Provider
    echo -e "${BOLD}AI Provider${NC}"
    echo -e "  1) Anthropic (Claude) — recommended"
    echo -e "  2) OpenAI (GPT-4o)"
    echo ""
    read -rp "$(echo -e "${BLUE}?${NC} Choose provider [1]: ")" AI_CHOICE < /dev/tty
    AI_CHOICE="${AI_CHOICE:-1}"

    case "$AI_CHOICE" in
        1)
            AI_PROVIDER="anthropic"
            AI_MODEL="anthropic/claude-sonnet-4-20250514"
            KEY_NAME="anthropicApiKey"
            echo -e "  Get your key at: ${BLUE}https://console.anthropic.com${NC} > API Keys"
            ;;
        2)
            AI_PROVIDER="openai"
            AI_MODEL="openai/gpt-4o"
            KEY_NAME="openaiApiKey"
            echo -e "  Get your key at: ${BLUE}https://platform.openai.com${NC} > API keys"
            ;;
        *)
            log_error "Invalid choice. Run the installer again."
            exit 1
            ;;
    esac

    echo ""
    read -rp "$(echo -e "${BLUE}?${NC} API key: ")" API_KEY < /dev/tty
    if [[ -z "$API_KEY" ]]; then
        log_error "API key cannot be empty."
        exit 1
    fi
    echo ""

    # Telegram bot token
    echo -e "${BOLD}Telegram Bot${NC}"
    echo -e "  Create a bot: open Telegram > search @BotFather > send /newbot"
    echo ""
    read -rp "$(echo -e "${BLUE}?${NC} Telegram bot token (123456789:AAF...): ")" TELEGRAM_TOKEN < /dev/tty
    if [[ -z "$TELEGRAM_TOKEN" ]]; then
        log_error "Telegram bot token cannot be empty."
        exit 1
    fi
    echo ""
fi

# Export for child scripts
export TAILSCALE_AUTH_KEY
export AI_PROVIDER AI_MODEL KEY_NAME API_KEY
export TELEGRAM_TOKEN

# ── Download / clone the repository ──────────────────────────────────────────

echo -e "${BOLD}${BLUE}[0/${TOTAL_PHASES}]${NC} ${BOLD}Preparing installer${NC}"
echo ""

if [[ -d "${INSTALL_DIR}/.git" ]]; then
    log_info "Repository already exists at ${INSTALL_DIR}. Updating..."
    cd "$INSTALL_DIR"
    if ! git pull --ff-only 2>/dev/null; then
        log_warn "Git pull failed — re-downloading fresh copy..."
        cd /
        rm -rf "$INSTALL_DIR"
    fi
fi

if [[ ! -d "$INSTALL_DIR" ]]; then
    # Try git clone first, fall back to tarball
    if command -v git &>/dev/null; then
        log_info "Cloning repository to ${INSTALL_DIR}..."
        git clone "$REPO_URL" "$INSTALL_DIR" 2>/dev/null || {
            log_warn "git clone failed. Trying tarball download..."
            mkdir -p "$INSTALL_DIR"
            curl -fsSL "https://github.com/nipisarev/OpenClawGuides/archive/refs/heads/main.tar.gz" | \
                tar -xz --strip-components=1 -C "$INSTALL_DIR" 2>/dev/null || {
                    log_error "Failed to download the repository. Check your internet connection."
                    exit 1
                }
        }
    else
        # git not installed yet — use curl + tar
        log_info "git not available yet. Downloading tarball..."
        mkdir -p "$INSTALL_DIR"
        curl -fsSL "https://github.com/nipisarev/OpenClawGuides/archive/refs/heads/main.tar.gz" | \
            tar -xz --strip-components=1 -C "$INSTALL_DIR" 2>/dev/null || {
                log_error "Failed to download the repository."
                exit 1
            }
    fi
fi

# Verify scripts exist
if [[ ! -f "${SCRIPTS_DIR}/common.sh" ]]; then
    log_error "Installation scripts not found at ${SCRIPTS_DIR}/. Aborting."
    exit 1
fi

log_success "Installer ready at ${INSTALL_DIR}"
echo ""

# ── Phase 1: Initial Server Setup ───────────────────────────────────────────

echo -e "${BOLD}${BLUE}[1/${TOTAL_PHASES}]${NC} ${BOLD}Phase 1: Initial Server Setup${NC}"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
run_phase 1 "Initial Setup" "${SCRIPTS_DIR}/01-setup-server.sh"
echo ""

log_info "Verifying SSH connectivity before security hardening..."
if type verify_ssh_access &>/dev/null && ! verify_ssh_access; then
    log_error "SSH access verification failed — cannot proceed with security hardening"
    log_error "Ensure SSH is working before running Phase 2"
    exit 1
fi

# ── Phase 2: Security Hardening ─────────────────────────────────────────────

echo -e "${BOLD}${BLUE}[2/${TOTAL_PHASES}]${NC} ${BOLD}Phase 2: Security Hardening${NC}"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
run_phase 2 "Security Hardening" "${SCRIPTS_DIR}/02-harden-server.sh"
echo ""

# ── Phase 3: OpenClaw Installation ──────────────────────────────────────────

echo -e "${BOLD}${BLUE}[3/${TOTAL_PHASES}]${NC} ${BOLD}Phase 3: OpenClaw Installation${NC}"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
run_phase 3 "OpenClaw Installation" "${SCRIPTS_DIR}/03-install-openclaw.sh"
echo ""

# ── Phase 4: First Agent Setup ──────────────────────────────────────────────

echo -e "${BOLD}${BLUE}[4/${TOTAL_PHASES}]${NC} ${BOLD}Phase 4: First Agent Setup${NC}"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Phase 4 runs as the openclaw user — pass collected info via env vars
OPENCLAW_HOME=$(eval echo "~openclaw")
OPENCLAW_PNPM_HOME=$(eval echo "~openclaw/.local/share/pnpm")
export PATH="$OPENCLAW_PNPM_HOME:$PATH"

# Credential backup file — survives config reshuffles from doctor --fix
CRED_BACKUP="${OPENCLAW_HOME}/.openclaw/.credentials.env"

if [[ "$ALREADY_INSTALLED" == true ]]; then
    # Re-run: restore from backup file, or prompt if backup missing
    if [[ -f "$CRED_BACKUP" ]]; then
        log_info "Restoring credentials from backup..."
        source "$CRED_BACKUP"
        if [[ -z "${CRED_TELEGRAM_TOKEN:-}" || -z "${CRED_API_KEY:-}" ]]; then
            log_warn "Backup file exists but has empty credentials — will re-prompt."
            rm -f "$CRED_BACKUP"
        else
            sudo -u openclaw bash -c "
                export PNPM_HOME=\"\${PNPM_HOME:-\$HOME/.local/share/pnpm}\"
                export PATH=\"\$PNPM_HOME:\$PATH\"

                # Restore AI model and key
                [[ -n '${CRED_AI_MODEL:-}' ]] && openclaw config set agents.defaults.model '${CRED_AI_MODEL:-}' 2>/dev/null || true
                [[ -n '${CRED_API_KEY:-}' && -n '${CRED_KEY_NAME:-}' ]] && openclaw config set 'agents.defaults.credentials.${CRED_KEY_NAME:-}' '${CRED_API_KEY:-}' 2>/dev/null || true

                # Restore Telegram channel
                [[ -n '${CRED_TELEGRAM_TOKEN:-}' ]] && {
                    openclaw channels add telegram --token '${CRED_TELEGRAM_TOKEN:-}' 2>/dev/null || \
                    openclaw config set channels.telegram.token '${CRED_TELEGRAM_TOKEN:-}' 2>/dev/null || true
                }

                # Ensure gateway auth token
                EXISTING=\$(openclaw config get gateway.auth.token 2>/dev/null || echo '')
                if [[ -z \"\$EXISTING\" || \"\$EXISTING\" == 'null' || \"\$EXISTING\" == 'REPLACE_WITH_GENERATED_TOKEN' ]]; then
                    if [[ -n '${CRED_AUTH_TOKEN:-}' ]]; then
                        openclaw config set gateway.auth.mode token 2>/dev/null || true
                        openclaw config set gateway.auth.token '${CRED_AUTH_TOKEN:-}' 2>/dev/null || true
                    else
                        NEW_TOKEN=\$(openssl rand -hex 32)
                        openclaw config set gateway.auth.mode token 2>/dev/null || true
                        openclaw config set gateway.auth.token \"\$NEW_TOKEN\" 2>/dev/null || true
                    fi
                fi

                # Re-apply security settings (idempotent)
                openclaw config set agents.defaults.sandbox.mode all 2>/dev/null || true
                openclaw config set agents.defaults.tools.profile minimal 2>/dev/null || true
                openclaw config set session.dmScope per-channel-peer 2>/dev/null || true
                openclaw config set channels.telegram.linkPreview false 2>/dev/null || true
            " 2>/dev/null || log_warn "Credential restoration had issues."
            log_success "Credentials restored from backup."
        fi
    fi

    if [[ -f "$CRED_BACKUP" ]]; then
        : # Already restored above
    else
        log_warn "No credential backup found — need to re-enter credentials."
        echo ""
        echo -e "  ${BOLD}AI Provider${NC}"
        echo -e "    1) Anthropic (Claude)"
        echo -e "    2) OpenAI (GPT-4o)"
        echo ""
        read -rp "$(echo -e "${BLUE}?${NC} Choose provider [1]: ")" AI_CHOICE < /dev/tty
        AI_CHOICE="${AI_CHOICE:-1}"
        case "$AI_CHOICE" in
            1)
                AI_PROVIDER="anthropic"
                AI_MODEL="anthropic/claude-sonnet-4-20250514"
                KEY_NAME="anthropicApiKey"
                ;;
            2)
                AI_PROVIDER="openai"
                AI_MODEL="openai/gpt-4o"
                KEY_NAME="openaiApiKey"
                ;;
            *)
                log_error "Invalid choice. Run the installer again."
                exit 1
                ;;
        esac
        echo ""
        read -rp "$(echo -e "${BLUE}?${NC} API key: ")" API_KEY < /dev/tty
        if [[ -z "$API_KEY" ]]; then
            log_error "API key cannot be empty."
            exit 1
        fi
        echo ""
        read -rp "$(echo -e "${BLUE}?${NC} Telegram bot token (123456789:AAF...): ")" TELEGRAM_TOKEN < /dev/tty
        if [[ -z "$TELEGRAM_TOKEN" ]]; then
            log_error "Telegram bot token cannot be empty."
            exit 1
        fi
        echo ""
        ALREADY_INSTALLED=false
    fi
fi

if [[ "$ALREADY_INSTALLED" != true ]]; then
    log_info "Configuring first agent..."

    sudo -u openclaw bash -c "
        export PNPM_HOME=\"\${PNPM_HOME:-\$HOME/.local/share/pnpm}\"
        export PATH=\"\$PNPM_HOME:\$PATH\"

        openclaw config set agents.defaults.model '${AI_MODEL}' 2>/dev/null || true
        openclaw config set 'agents.defaults.credentials.${KEY_NAME}' '${API_KEY}' 2>/dev/null || true
        openclaw config set agents.defaults.sandbox.mode all 2>/dev/null || true
        openclaw config set agents.defaults.tools.profile minimal 2>/dev/null || true
        openclaw config set session.dmScope per-channel-peer 2>/dev/null || true
        openclaw channels add telegram --token '${TELEGRAM_TOKEN}' 2>/dev/null || \
        openclaw config set channels.telegram.token '${TELEGRAM_TOKEN}' 2>/dev/null || true
        openclaw config set channels.telegram.linkPreview false 2>/dev/null || true
    " 2>/dev/null || log_warn "Some agent configuration steps may need manual attention."

    # Generate gateway auth token
    GW_AUTH_TOKEN=$(openssl rand -hex 32)
    sudo -u openclaw bash -c "
        export PNPM_HOME=\"\${PNPM_HOME:-\$HOME/.local/share/pnpm}\"
        export PATH=\"\$PNPM_HOME:\$PATH\"
        openclaw config set gateway.auth.mode token 2>/dev/null || true
        openclaw config set gateway.auth.token '${GW_AUTH_TOKEN}' 2>/dev/null || true
    " 2>/dev/null || true
    echo -e "  ${YELLOW}IMPORTANT:${NC} Save this gateway auth token:"
    echo -e "  ${BOLD}${GW_AUTH_TOKEN}${NC}"

    # Save credentials to backup file (survives doctor --fix reshuffles)
    mkdir -p "$(dirname "$CRED_BACKUP")"
    cat > "$CRED_BACKUP" << CREDEOF
# OpenClaw credential backup — auto-generated, do not edit
# Used by installer re-runs to restore credentials after config changes
CRED_AI_MODEL='${AI_MODEL}'
CRED_KEY_NAME='${KEY_NAME}'
CRED_API_KEY='${API_KEY}'
CRED_TELEGRAM_TOKEN='${TELEGRAM_TOKEN}'
CRED_AUTH_TOKEN='${GW_AUTH_TOKEN}'
CREDEOF
    chown openclaw:openclaw "$CRED_BACKUP"
    chmod 600 "$CRED_BACKUP"
    log_info "Credentials backed up to ${CRED_BACKUP} (600 — owner only)."
fi

# Start/restart the Gateway
log_info "Starting OpenClaw Gateway..."
systemctl restart openclaw 2>/dev/null || systemctl start openclaw 2>/dev/null || {
    sudo -u openclaw bash -c '
        export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
        export PATH="$PNPM_HOME:$PATH"
        openclaw gateway run &
    ' 2>/dev/null || true
}

sleep 3
log_success "Phase 4 complete."
echo ""

# ── Final Summary ────────────────────────────────────────────────────────────

TS_IP=$(tailscale ip -4 2>/dev/null || echo "(run 'tailscale up' to connect)")

echo -e "${GREEN}"
cat << 'DONE'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                 Installation Complete!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DONE
echo -e "${NC}"

echo -e "  ${BOLD}Tailscale IP:${NC}     ${TS_IP}"
echo -e "  ${BOLD}AI Provider:${NC}      ${AI_PROVIDER}"
echo -e "  ${BOLD}Model:${NC}            ${AI_MODEL}"
echo -e "  ${BOLD}Channel:${NC}          Telegram"
echo -e "  ${BOLD}Gateway:${NC}          127.0.0.1:18789 (loopback only)"
echo -e "  ${BOLD}Config:${NC}           ${OPENCLAW_HOME}/.openclaw/openclaw.json5"
echo -e "  ${BOLD}Service:${NC}          systemctl status openclaw"
echo ""
echo -e "  ${YELLOW}Test your bot:${NC}"
echo -e "    Open Telegram and send a message to your bot."
echo -e "    You should get an AI response within 5-15 seconds."
echo ""
echo -e "  ${YELLOW}SSH via Tailscale (recommended):${NC}"
echo -e "    ssh openclaw@${TS_IP}"
echo ""
echo -e "  ${BOLD}Security summary:${NC}"
echo -e "    UFW:        deny all, allow SSH + Tailscale"
echo -e "    Fail2ban:   5 retries → 1h ban"
echo -e "    SSH:        key-only, root disabled, config locked"
echo -e "    Sandbox:    all (Docker isolation)"
echo -e "    Session:    per-channel-peer (isolated)"
echo -e "    Plugins:    disabled"
echo ""
echo -e "  ${YELLOW}Optional next steps (run manually):${NC}"
echo ""
echo -e "    ${BOLD}Multi-agent setup${NC} (3 specialized agents):"
echo -e "      sudo bash ${SCRIPTS_DIR}/05-multi-agent.sh"
echo ""
echo -e "    ${BOLD}Maintenance automation${NC} (nightly audit + hourly backups):"
echo -e "      sudo bash ${SCRIPTS_DIR}/06-maintenance.sh"
echo ""
echo -e "  ${YELLOW}Useful commands:${NC}"
echo -e "    openclaw status            — is Gateway running?"
echo -e "    openclaw logs              — view activity"
echo -e "    openclaw doctor            — health check"
echo -e "    openclaw security audit    — security check (50+ items)"
echo -e "    openclaw update            — update to latest version"
echo ""
