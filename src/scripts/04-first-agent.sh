#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Phase 4 — First Agent Setup
#
# What this script does:
#   1. Prompts for your AI provider API key (Anthropic or OpenAI)
#   2. Prompts for your Telegram bot token (from @BotFather)
#   3. Configures the first agent with the chosen AI model
#   4. Starts the OpenClaw Gateway service
#   5. Verifies the bot is responding
#
# Run as the 'openclaw' user (not root).
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Allow env vars to be pre-set (e.g. from install.sh) — skip prompts when set
AI_PROVIDER="${AI_PROVIDER:-}"
AI_MODEL="${AI_MODEL:-}"
KEY_NAME="${KEY_NAME:-}"
API_KEY="${API_KEY:-}"
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"

TOTAL_STEPS=5

# This script should NOT run as root — OpenClaw runs as a regular user
if [[ $EUID -eq 0 ]]; then
    log_error "Do not run this script as root. Run as the 'openclaw' user:"
    echo -e "  ${BOLD}sudo -u openclaw bash ${BASH_SOURCE[0]}${NC}"
    exit 1
fi

# Verify openclaw CLI is available
if ! is_installed openclaw; then
    # Try adding pnpm global bin to PATH
    export PATH="$PATH:$(pnpm bin -g 2>/dev/null || echo "")"
    if ! is_installed openclaw; then
        log_error "openclaw CLI not found. Did Phase 3 complete successfully?"
        exit 1
    fi
fi

print_banner
echo -e "${BOLD}Phase 4: First Agent Setup${NC}"
echo ""

# ── Step 1: AI Provider API Key ─────────────────────────────────────────────
step 1 $TOTAL_STEPS "Configuring AI provider"

if [[ -n "$AI_PROVIDER" && -n "$API_KEY" ]]; then
    log_info "Using pre-configured AI provider: ${AI_PROVIDER}"

    # Derive defaults if not explicitly set
    if [[ "$AI_PROVIDER" == "anthropic" ]]; then
        AI_MODEL="${AI_MODEL:-anthropic/claude-sonnet-4-20250514}"
        KEY_NAME="${KEY_NAME:-anthropicApiKey}"
    elif [[ "$AI_PROVIDER" == "openai" ]]; then
        AI_MODEL="${AI_MODEL:-openai/gpt-4o}"
        KEY_NAME="${KEY_NAME:-openaiApiKey}"
    fi

    log_info "Using model: ${AI_MODEL}"
else
    echo ""
    echo -e "  Which AI provider do you want to use?"
    echo -e "    ${BOLD}1)${NC} Anthropic (Claude) — recommended"
    echo -e "    ${BOLD}2)${NC} OpenAI (GPT-4o)"
    echo ""

    PROVIDER_CHOICE=$(prompt_input "Enter choice (1 or 2)" "1")

    case "$PROVIDER_CHOICE" in
        1)
            AI_PROVIDER="anthropic"
            AI_MODEL="anthropic/claude-sonnet-4-20250514"
            KEY_NAME="anthropicApiKey"
            echo ""
            echo -e "  ${BLUE}Get your API key at:${NC} ${BOLD}https://console.anthropic.com${NC}"
            echo -e "  Go to API Keys > Create Key > Copy the key"
            echo ""
            API_KEY=$(prompt_input "Paste your Anthropic API key (starts with sk-ant-)")
            ;;
        2)
            AI_PROVIDER="openai"
            AI_MODEL="openai/gpt-4o"
            KEY_NAME="openaiApiKey"
            echo ""
            echo -e "  ${BLUE}Get your API key at:${NC} ${BOLD}https://platform.openai.com${NC}"
            echo -e "  Go to API keys > Create new secret key > Copy the key"
            echo ""
            API_KEY=$(prompt_input "Paste your OpenAI API key (starts with sk-)")
            ;;
        *)
            log_error "Invalid choice. Please enter 1 or 2."
            exit 1
            ;;
    esac

    if [[ -z "$API_KEY" ]]; then
        log_error "API key cannot be empty."
        exit 1
    fi
fi

# Configure the model and API key
log_info "Setting AI model to ${AI_MODEL}..."
openclaw config set agents.defaults.model "$AI_MODEL"

log_info "Saving API key securely..."
openclaw config set "agents.defaults.credentials.${KEY_NAME}" "$API_KEY"

# Enable full sandbox isolation
openclaw config set agents.defaults.sandbox.mode all
openclaw config set agents.defaults.tools.profile minimal

log_success "AI provider configured: ${AI_MODEL}"

# ── Step 2: Telegram Bot Token ───────────────────────────────────────────────
step 2 $TOTAL_STEPS "Configuring Telegram bot"

if [[ -n "$TELEGRAM_TOKEN" ]]; then
    log_info "Using pre-configured Telegram bot token."
else
    echo ""
    echo -e "  Create a Telegram bot via ${BOLD}@BotFather${NC}:"
    echo -e "    1. Open Telegram and search for ${BOLD}@BotFather${NC} (with blue checkmark)"
    echo -e "    2. Send ${BOLD}/newbot${NC}"
    echo -e "    3. Choose a display name (e.g. 'My AI Assistant')"
    echo -e "    4. Choose a username ending in 'bot' (e.g. 'my_ai_helper_bot')"
    echo -e "    5. Copy the token BotFather gives you"
    echo ""

    TELEGRAM_TOKEN=$(prompt_input "Paste your Telegram bot token (format: 123456789:AAF...)")

    if [[ -z "$TELEGRAM_TOKEN" ]]; then
        log_error "Telegram bot token cannot be empty."
        exit 1
    fi
fi

# Validate token format (basic check)
if [[ ! "$TELEGRAM_TOKEN" =~ ^[0-9]+:.+ ]]; then
    log_warn "Token format looks unusual. Expected format: 123456789:AAF..."
    if ! confirm "Continue anyway?"; then
        exit 1
    fi
fi

# Add Telegram channel
log_info "Adding Telegram channel..."
openclaw channels add telegram --token "$TELEGRAM_TOKEN" 2>/dev/null || {
    log_warn "Could not add channel via CLI flag. You may need to run 'openclaw channels add telegram' interactively."
}

# Disable link previews to prevent data exfiltration (IDPI mitigation)
openclaw config set channels.telegram.linkPreview false

log_success "Telegram bot configured."

# ── Step 3: Configure agent security ────────────────────────────────────────
step 3 $TOTAL_STEPS "Applying agent security settings"

# These may already be set in the config file from Phase 3, but ensure via CLI
openclaw config set agents.defaults.sandbox.mode all
openclaw config set agents.defaults.tools.profile minimal
openclaw config set session.dmScope per-channel-peer

log_success "Agent security: sandbox=all, tools=minimal, session=per-channel-peer"

# ── Step 4: Start Gateway ───────────────────────────────────────────────────
step 4 $TOTAL_STEPS "Starting OpenClaw Gateway"

# Try restarting via openclaw CLI first, fall back to systemd
if openclaw gateway restart 2>/dev/null; then
    log_success "Gateway started via openclaw CLI."
else
    log_info "Trying systemd restart..."
    sudo systemctl restart openclaw 2>/dev/null || {
        log_warn "Could not restart via systemd. Starting in foreground mode..."
        log_info "Run 'openclaw gateway run' to start manually."
    }
fi

# Give it a moment to start
sleep 3

# ── Step 5: Verify ──────────────────────────────────────────────────────────
step 5 $TOTAL_STEPS "Verifying setup"

# Check Gateway status
if openclaw status 2>/dev/null | grep -qi "running"; then
    log_success "Gateway is running."
else
    log_warn "Could not confirm Gateway status. Check with: openclaw status"
fi

# Check channels
if openclaw channels list 2>/dev/null | grep -qi "telegram"; then
    log_success "Telegram channel is configured."
else
    log_warn "Could not confirm Telegram channel. Check with: openclaw channels list"
fi

# Run a quick doctor check
if openclaw doctor 2>/dev/null; then
    log_success "Health check passed."
else
    log_warn "Some health checks may need attention. Run: openclaw doctor"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} Phase 4 complete! Your AI assistant is live!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}AI Provider:${NC}  ${AI_PROVIDER}"
echo -e "  ${BOLD}Model:${NC}        ${AI_MODEL}"
echo -e "  ${BOLD}Channel:${NC}      Telegram"
echo ""
echo -e "  ${YELLOW}Test your bot now:${NC}"
echo -e "    1. Open Telegram"
echo -e "    2. Find your bot by username"
echo -e "    3. Send: ${BOLD}Hello!${NC}"
echo -e "    4. You should get an AI response within 5-15 seconds"
echo ""
echo -e "  ${YELLOW}Useful commands:${NC}"
echo -e "    ${BOLD}openclaw status${NC}           — check if Gateway is running"
echo -e "    ${BOLD}openclaw logs${NC}             — view recent activity"
echo -e "    ${BOLD}openclaw doctor${NC}           — run health checks"
echo -e "    ${BOLD}openclaw channels list${NC}    — list configured channels"
echo ""
echo -e "  Next steps (optional):"
echo -e "    ${BOLD}bash 05-multi-agent.sh${NC}    — set up multiple specialized agents"
echo -e "    ${BOLD}sudo bash 06-maintenance.sh${NC} — install nightly audits and backups"
echo ""
