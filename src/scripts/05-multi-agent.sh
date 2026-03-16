#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Phase 5 — Multi-Agent Setup
#
# What this script does:
#   1. Creates workspace directories for each agent
#   2. Creates /etc/openclaw/env with per-agent API key variables
#   3. Deploys gateway.yaml multi-agent configuration
#   4. Protects SOUL.md and MEMORY.md with chattr +i
#   5. Recreates sandbox containers and restarts the Gateway
#
# Run as root on a server that completed Phase 4.
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TOTAL_STEPS=5
OPENCLAW_USER="openclaw"
OPENCLAW_HOME=$(eval echo "~${OPENCLAW_USER}")
OPENCLAW_DIR="${OPENCLAW_HOME}/.openclaw"

check_root
check_ubuntu

print_banner
echo -e "${BOLD}Phase 5: Multi-Agent Setup${NC}"
echo ""
echo -e "  This sets up three specialized agents:"
echo -e "    ${BOLD}assistant${NC}   — General Q&A (Claude, minimal tools, no file access)"
echo -e "    ${BOLD}coder${NC}       — Code & files (GPT-4o, coding tools, scoped workspace)"
echo -e "    ${BOLD}researcher${NC}  — Web search (Claude, browser only, no file access)"
echo ""

# ── Step 1: Create workspace directories ─────────────────────────────────────
step 1 $TOTAL_STEPS "Creating workspace directories"

WORKSPACES_BASE="/opt/openclaw/workspaces"

# Create the coder workspace (other agents don't need workspace dirs)
if [[ -d "${WORKSPACES_BASE}/coder" ]]; then
    log_warn "Coder workspace already exists at ${WORKSPACES_BASE}/coder"
else
    mkdir -p "${WORKSPACES_BASE}/coder"
    chown "${OPENCLAW_USER}:${OPENCLAW_USER}" "${WORKSPACES_BASE}/coder"
    log_success "Created coder workspace: ${WORKSPACES_BASE}/coder"
fi

# Ensure parent directory ownership
chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" /opt/openclaw 2>/dev/null || {
    mkdir -p /opt/openclaw
    chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" /opt/openclaw
}
log_info "Workspace directories ready."

# ── Step 2: Create .env file with agent API keys ────────────────────────────
step 2 $TOTAL_STEPS "Setting up per-agent API keys"

ENV_DIR="/etc/openclaw"
ENV_FILE="${ENV_DIR}/env"

mkdir -p "$ENV_DIR"

if [[ -f "$ENV_FILE" ]]; then
    log_warn "Environment file already exists at ${ENV_FILE}"
    if ! confirm "Overwrite with new API keys?"; then
        log_info "Keeping existing environment file."
    else
        rm -f "$ENV_FILE"
    fi
fi

if [[ ! -f "$ENV_FILE" ]]; then
    echo ""
    echo -e "  ${YELLOW}Each agent can use its own API key for independent cost tracking.${NC}"
    echo -e "  You can use the same key for multiple agents if preferred."
    echo ""

    # Assistant (Anthropic)
    echo -e "  ${BOLD}Agent: assistant${NC} (Claude)"
    ASSISTANT_KEY=$(prompt_input "  Anthropic API key for assistant (sk-ant-...)")

    # Coder (OpenAI)
    echo ""
    echo -e "  ${BOLD}Agent: coder${NC} (GPT-4o)"
    CODER_KEY=$(prompt_input "  OpenAI API key for coder (sk-...)")

    # Researcher (Anthropic)
    echo ""
    echo -e "  ${BOLD}Agent: researcher${NC} (Claude)"
    RESEARCHER_KEY=$(prompt_input "  Anthropic API key for researcher (sk-ant-..., or press Enter to reuse assistant key)" "$ASSISTANT_KEY")

    cat > "$ENV_FILE" << EOF
# OpenClaw per-agent API keys
# Referenced in gateway.yaml as \${AGENT_ASSISTANT_ANTHROPIC_KEY} etc.
AGENT_ASSISTANT_ANTHROPIC_KEY=${ASSISTANT_KEY}
AGENT_CODER_OPENAI_KEY=${CODER_KEY}
AGENT_RESEARCHER_ANTHROPIC_KEY=${RESEARCHER_KEY}
EOF

    # Restrict access — only the openclaw user can read this file
    chmod 600 "$ENV_FILE"
    chown "${OPENCLAW_USER}:${OPENCLAW_USER}" "$ENV_FILE"
    log_success "API keys saved to ${ENV_FILE} (permissions: 600)."
fi

# Ensure systemd loads the env file
SYSTEMD_OVERRIDE_DIR="/etc/systemd/system/openclaw.service.d"
mkdir -p "$SYSTEMD_OVERRIDE_DIR"

if [[ ! -f "${SYSTEMD_OVERRIDE_DIR}/env.conf" ]]; then
    cat > "${SYSTEMD_OVERRIDE_DIR}/env.conf" << EOF
[Service]
EnvironmentFile=${ENV_FILE}
EOF
    systemctl daemon-reload
    log_info "systemd configured to load environment file on startup."
else
    log_warn "systemd env override already exists."
fi

# ── Step 3: Deploy gateway.yaml ─────────────────────────────────────────────
step 3 $TOTAL_STEPS "Deploying multi-agent gateway.yaml"

GATEWAY_YAML="${OPENCLAW_DIR}/gateway.yaml"

if [[ -f "$GATEWAY_YAML" ]]; then
    log_warn "gateway.yaml already exists."
    if ! confirm "Overwrite with multi-agent template?"; then
        log_info "Keeping existing gateway.yaml."
    else
        cp "$GATEWAY_YAML" "${GATEWAY_YAML}.backup-$(date +%Y%m%d%H%M%S)"
        rm -f "$GATEWAY_YAML"
    fi
fi

if [[ ! -f "$GATEWAY_YAML" ]]; then
    sudo -u "$OPENCLAW_USER" cat > "$GATEWAY_YAML" << 'EOF'
# Multi-agent gateway configuration for OpenClaw
# Each agent runs in its own Docker container with scoped permissions.

gateway:
  bind: loopback
  port: 18789
  auth:
    mode: token

agents:
  # Defaults applied to all agents unless overridden
  defaults:
    sandbox:
      mode: all
      scope: dedicated
      docker: true
      memory: "512m"
      cpus: "0.5"
    tools:
      profile: minimal
    workspaceAccess: none

  definitions:
    # General Q&A — no tools, no file access, minimal attack surface
    assistant:
      model:
        provider: anthropic
        name: claude-sonnet-4-20250514
      tools:
        profile: minimal
      sandbox:
        mode: all
        scope: dedicated
        workspaceAccess: none
      credentials:
        anthropicApiKey: ${AGENT_ASSISTANT_ANTHROPIC_KEY}

    # Code generation — can read/write files and execute commands,
    # but only within its scoped workspace directory, no internet access
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

    # Web research — can browse in sandboxed browser,
    # but cannot write files or execute commands
    researcher:
      model:
        provider: anthropic
        name: claude-sonnet-4-20250514
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

channels:
  telegram:
    defaultAgent: assistant
    agentRouting:
      /coder: coder
      /research: researcher
EOF

    chown "${OPENCLAW_USER}:${OPENCLAW_USER}" "$GATEWAY_YAML"
    log_success "gateway.yaml deployed with 3 agents (assistant, coder, researcher)."
fi

# ── Step 4: Protect identity files ───────────────────────────────────────────
step 4 $TOTAL_STEPS "Protecting agent identity files (SOUL.md, MEMORY.md)"

WORKSPACE_DIR="${OPENCLAW_HOME}/openclaw/workspace"

# SOUL.md and MEMORY.md may be in different locations depending on setup
SEARCH_DIRS=(
    "${OPENCLAW_HOME}/openclaw/workspace"
    "${OPENCLAW_HOME}/.openclaw"
    "${OPENCLAW_DIR}"
)

PROTECTED_COUNT=0
for dir in "${SEARCH_DIRS[@]}"; do
    for file in SOUL.md MEMORY.md; do
        filepath="${dir}/${file}"
        if [[ -f "$filepath" ]]; then
            # Check if already immutable
            if lsattr "$filepath" 2>/dev/null | grep -q "\-i\-"; then
                log_warn "${filepath} is already immutable."
            else
                safe_chattr "$filepath"
                log_info "Protected: ${filepath} (chattr +i)"
                ((PROTECTED_COUNT++))
            fi
        fi
    done
done

if [[ $PROTECTED_COUNT -eq 0 ]]; then
    log_warn "No SOUL.md or MEMORY.md files found yet."
    log_info "After first agent interaction, protect them manually:"
    echo -e "    ${BOLD}sudo chattr +i ~/openclaw/workspace/SOUL.md${NC}"
    echo -e "    ${BOLD}sudo chattr +i ~/openclaw/workspace/MEMORY.md${NC}"
else
    log_success "Protected ${PROTECTED_COUNT} identity file(s) from modification."
fi

echo ""
echo -e "  ${YELLOW}To edit protected files later:${NC}"
echo -e "    sudo chattr -i <file>    # unlock"
echo -e "    nano <file>              # edit"
echo -e "    sudo chattr +i <file>    # re-lock"

# ── Step 5: Recreate sandboxes and restart ───────────────────────────────────
step 5 $TOTAL_STEPS "Recreating sandboxes and restarting Gateway"

# Recreate sandbox containers
log_info "Recreating sandbox containers for all agents..."
sudo -u "$OPENCLAW_USER" bash -c '
    export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
    export PATH="$PNPM_HOME:$PATH"
    openclaw sandbox recreate 2>/dev/null || echo "sandbox recreate: will be created on first use"
'

# Restart Gateway
log_info "Restarting Gateway..."
systemctl restart openclaw 2>/dev/null || {
    sudo -u "$OPENCLAW_USER" bash -c '
        export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
        export PATH="$PNPM_HOME:$PATH"
        openclaw gateway restart 2>/dev/null || true
    '
}

sleep 3
verify_service openclaw || {
    log_error "OpenClaw service failed to start after restart"
    exit 1
}

# Verify
sudo -u "$OPENCLAW_USER" bash -c '
    export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
    export PATH="$PNPM_HOME:$PATH"
    openclaw sandbox list 2>/dev/null || echo "Run: openclaw sandbox list"
' || true

log_success "Multi-agent setup applied."

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} Phase 5 complete! Multi-agent system is running.${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}Agents:${NC}"
echo -e "    assistant   — Claude Sonnet (default, minimal tools)"
echo -e "    coder       — GPT-4o (coding tools, workspace: ${WORKSPACES_BASE}/coder)"
echo -e "    researcher  — Claude Sonnet (browser only, no file access)"
echo ""
echo -e "  ${BOLD}Telegram commands:${NC}"
echo -e "    (any message)  → assistant"
echo -e "    /coder          → switch to coder agent"
echo -e "    /research       → switch to researcher agent"
echo ""
echo -e "  ${BOLD}Container limits:${NC} 512MB RAM, 0.5 CPU per agent"
echo ""
echo -e "  ${YELLOW}Verify with:${NC}"
echo -e "    ${BOLD}openclaw sandbox list${NC}      — check all containers are running"
echo -e "    ${BOLD}openclaw sandbox explain${NC}   — show access breakdown per agent"
echo -e "    ${BOLD}openclaw security audit --deep${NC}  — full security check"
echo ""
echo -e "  Next step: ${BOLD}sudo bash 06-maintenance.sh${NC}"
echo ""
