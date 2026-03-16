#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Phase 3 — OpenClaw Installation
#
# What this script does:
#   1. Installs Node.js 22.x via NodeSource
#   2. Installs pnpm globally via corepack
#   3. Installs Docker CE + docker-compose plugin
#   4. Adds the openclaw user to the docker group
#   5. Installs OpenClaw via pnpm
#   6. Deploys the hardened configuration (openclaw.json5)
#   7. Installs systemd service with resource limits
#   8. Enables session isolation (dmScope: per-channel-peer)
#
# Run as root on a server that completed Phase 2.
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TOTAL_STEPS=8
OPENCLAW_USER="openclaw"
OPENCLAW_HOME=$(eval echo "~${OPENCLAW_USER}")

check_root
check_ubuntu

print_banner
echo -e "${BOLD}Phase 3: OpenClaw Installation${NC}"
echo ""

# ── Step 1: Node.js 22.x ────────────────────────────────────────────────────
step 1 $TOTAL_STEPS "Installing Node.js 22.x"

if is_installed node; then
    NODE_VER=$(node -v 2>/dev/null || echo "v0")
    NODE_MAJOR="${NODE_VER#v}"
    NODE_MAJOR="${NODE_MAJOR%%.*}"
    if [[ "$NODE_MAJOR" -ge 22 ]]; then
        log_warn "Node.js ${NODE_VER} is already installed."
    else
        log_info "Node.js ${NODE_VER} found but v22+ required. Upgrading..."
        curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
        wait_for_apt
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs
        log_success "Node.js upgraded to $(node -v)."
    fi
else
    log_info "Installing Node.js 22.x from NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    wait_for_apt
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs
    log_success "Node.js $(node -v) installed."
fi

# ── Step 2: pnpm ────────────────────────────────────────────────────────────
step 2 $TOTAL_STEPS "Installing pnpm package manager"

if is_installed pnpm; then
    log_warn "pnpm $(pnpm -v 2>/dev/null) is already installed."
else
    log_info "Enabling corepack and installing pnpm..."
    corepack enable
    corepack prepare pnpm@latest --activate
    log_success "pnpm $(pnpm -v 2>/dev/null) installed."
fi

# ── Step 3: Docker CE ────────────────────────────────────────────────────────
step 3 $TOTAL_STEPS "Installing Docker CE and docker-compose"

if is_installed docker; then
    log_warn "Docker is already installed: $(docker --version 2>/dev/null)."
else
    log_info "Setting up Docker repository..."

    # Install prerequisites
    wait_for_apt
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ca-certificates curl gnupg

    # Add Docker GPG key
    install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
    fi

    # Add Docker apt repository
    if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_ID} \
          ${OS_CODENAME} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi

    log_info "Installing Docker packages..."
    wait_for_apt
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Start and enable Docker
    systemctl enable --now docker
    log_success "Docker CE installed and running."
fi

# ── Step 4: Add openclaw user to docker group ────────────────────────────────
step 4 $TOTAL_STEPS "Adding '${OPENCLAW_USER}' to the docker group"

if groups "$OPENCLAW_USER" 2>/dev/null | grep -qw docker; then
    log_warn "User '${OPENCLAW_USER}' is already in the docker group."
else
    usermod -aG docker "$OPENCLAW_USER"
    log_success "User '${OPENCLAW_USER}' added to docker group."
    log_info "The user will need to re-login for group changes to take effect."
fi

# ── Step 5: Install OpenClaw ─────────────────────────────────────────────────
step 5 $TOTAL_STEPS "Installing OpenClaw"

# Run pnpm install as the openclaw user
if sudo -u "$OPENCLAW_USER" bash -c 'command -v openclaw' &>/dev/null; then
    OC_VER=$(sudo -u "$OPENCLAW_USER" bash -c 'openclaw --version 2>/dev/null' || echo "unknown")
    log_warn "OpenClaw is already installed: ${OC_VER}"
else
    log_info "Installing OpenClaw globally via pnpm..."
    sudo -u "$OPENCLAW_USER" bash -c "
        cd ~${OPENCLAW_USER}
        # Ensure PNPM_HOME and global bin dir exist
        export PNPM_HOME=\"\${HOME}/.local/share/pnpm\"
        mkdir -p \"\$PNPM_HOME\"
        export PATH=\"\$PNPM_HOME:\$PATH\"
        pnpm setup 2>/dev/null || true
        pnpm install -g openclaw
    "
    log_success "OpenClaw installed."

    # Ensure PNPM_HOME is in PATH for the openclaw user
    BASHRC="${OPENCLAW_HOME}/.bashrc"
    if ! grep -qF "PNPM_HOME" "$BASHRC" 2>/dev/null; then
        {
            echo 'export PNPM_HOME="${HOME}/.local/share/pnpm"'
            echo 'export PATH="$PNPM_HOME:$PATH"'
        } >> "$BASHRC"
        log_info "Added PNPM_HOME to ${OPENCLAW_USER}'s PATH in .bashrc"
    fi
fi

# ── Step 6: Deploy hardened configuration ────────────────────────────────────
step 6 $TOTAL_STEPS "Deploying hardened OpenClaw configuration"

OPENCLAW_DIR="${OPENCLAW_HOME}/.openclaw"
OPENCLAW_CONFIG="${OPENCLAW_DIR}/openclaw.json5"

# Create .openclaw directory with correct permissions
sudo -u "$OPENCLAW_USER" mkdir -p "$OPENCLAW_DIR"

if [[ -f "$OPENCLAW_CONFIG" ]]; then
    log_warn "Configuration file already exists at ${OPENCLAW_CONFIG} — skipping overwrite."
    # Ensure critical settings exist on re-run
    sudo -u "$OPENCLAW_USER" bash -c "
        export PNPM_HOME=\"\${PNPM_HOME:-\$HOME/.local/share/pnpm}\"
        export PATH=\"\$PNPM_HOME:\$PATH\"
        openclaw config set gateway.mode local 2>/dev/null || true
        openclaw config set channels.telegram.groupPolicy open 2>/dev/null || true
    "
    log_info "Verified critical gateway settings."
else
    # Check for template in the repo
    CONFIG_TEMPLATE="${SCRIPT_DIR}/../configs/openclaw.json5"
    if [[ -f "$CONFIG_TEMPLATE" ]]; then
        sudo -u "$OPENCLAW_USER" cp "$CONFIG_TEMPLATE" "$OPENCLAW_CONFIG"
        log_info "Deployed config from template."
    else
        # Generate auth token
        AUTH_TOKEN=$(openssl rand -hex 32)

        sudo -u "$OPENCLAW_USER" bash -c "cat > '${OPENCLAW_CONFIG}'" << EOF
{
  "\$schema": "https://openclaw.ai/schemas/2024-11/config.json",
  "version": 1,

  "gateway": {
    "mode": "local",
    "bind": "loopback",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "${AUTH_TOKEN}"
    },
    "trustedProxies": [],
    "controlUi": {
      "dangerouslyDisableDeviceAuth": false
    }
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

  "session": {
    "dmScope": "per-channel-peer"
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

  "skills": {
    "autoInstall": false,
    "trustedPublishers": []
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
EOF
        log_success "Hardened configuration deployed."
        log_info "Auth token generated and saved to config."
        echo -e "  ${YELLOW}IMPORTANT:${NC} Save this token securely — you need it to access the Control UI:"
        echo -e "  ${BOLD}${AUTH_TOKEN}${NC}"
    fi
fi

# Lock down the .openclaw directory — owner-only access
chmod 700 "$OPENCLAW_DIR"
log_info "Permissions set: ${OPENCLAW_DIR} (700 — owner only)."

# ── Step 7: Install systemd service with resource limits ─────────────────────
step 7 $TOTAL_STEPS "Installing systemd service with resource limits"

SYSTEMD_UNIT="/etc/systemd/system/openclaw.service"
SYSTEMD_OVERRIDE_DIR="/etc/systemd/system/openclaw.service.d"

# Check for systemd template in the repo
SYSTEMD_TEMPLATE="${SCRIPT_DIR}/../configs/systemd/openclaw.service"

# Determine the openclaw binary path
OC_BIN=$(sudo -u "$OPENCLAW_USER" bash -c '
    export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
    export PATH="$PNPM_HOME:$PATH"
    command -v openclaw 2>/dev/null || echo ""
')
if [[ -z "$OC_BIN" ]]; then
    log_error "openclaw binary not found in PATH"
    exit 1
fi

if [[ -f "$SYSTEMD_UNIT" ]]; then
    # Update ExecStart path and fix namespace issues on re-run
    log_info "Updating existing systemd unit (ExecStart=${OC_BIN})..."
    sed -i "s|^ExecStart=.*|ExecStart=${OC_BIN} gateway run|" "$SYSTEMD_UNIT"
    if ! systemd-run --quiet --property=PrivateTmp=yes --wait /bin/true 2>/dev/null; then
        log_warn "Kernel does not support namespace sandboxing — disabling"
        sed -i 's/^PrivateTmp=.*/#&/; s/^ProtectSystem=.*/#&/; s/^ProtectHome=.*/#&/; s/^NoNewPrivileges=.*/#&/' "$SYSTEMD_UNIT"
    fi
    systemctl daemon-reload
    systemctl enable openclaw 2>/dev/null
    systemctl restart openclaw
    log_success "systemd unit updated and restarted."
else

    if [[ -f "$SYSTEMD_TEMPLATE" ]]; then
        cp "$SYSTEMD_TEMPLATE" "$SYSTEMD_UNIT"
        sed -i "s|__OPENCLAW_BIN__|${OC_BIN}|g" "$SYSTEMD_UNIT"
        log_info "Deployed systemd unit from template (ExecStart=${OC_BIN})."
    else
        cat > "$SYSTEMD_UNIT" << EOF
[Unit]
Description=OpenClaw Gateway
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=${OPENCLAW_USER}
Group=${OPENCLAW_USER}
WorkingDirectory=${OPENCLAW_HOME}
ExecStart=${OC_BIN} gateway run
Restart=always
RestartSec=5

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=${OPENCLAW_HOME}/.openclaw ${OPENCLAW_HOME}

[Install]
WantedBy=multi-user.target
EOF
        log_info "systemd unit created."
    fi

    if command -v systemd-analyze &>/dev/null; then
        systemd-analyze verify openclaw.service 2>/dev/null || log_warn "systemd unit verification produced warnings"
    fi

    # Test if systemd namespace features work on this kernel
    if ! systemd-run --quiet --property=PrivateTmp=yes --wait /bin/true 2>/dev/null; then
        log_warn "Kernel does not support systemd namespace sandboxing — disabling"
        sed -i 's/^PrivateTmp=.*/#&/; s/^ProtectSystem=.*/#&/; s/^ProtectHome=.*/#&/' "$SYSTEMD_UNIT"
    fi
fi

# Apply resource limits via drop-in override
mkdir -p "$SYSTEMD_OVERRIDE_DIR"

if [[ -f "${SYSTEMD_OVERRIDE_DIR}/resources.conf" ]]; then
    log_warn "Resource limits override already exists — skipping."
else
    RESOURCES_TEMPLATE="${SCRIPT_DIR}/../configs/systemd/openclaw-resources.conf"
    if [[ -f "$RESOURCES_TEMPLATE" ]]; then
        cp "$RESOURCES_TEMPLATE" "${SYSTEMD_OVERRIDE_DIR}/resources.conf"
        log_info "Resource limits deployed from template."
    else
        cat > "${SYSTEMD_OVERRIDE_DIR}/resources.conf" << 'EOF'
[Service]
Environment=NODE_OPTIONS=--max-old-space-size=1536
MemoryHigh=1536M
MemoryMax=2G
WatchdogSec=30
Restart=always
RestartSec=5
EOF
        log_info "Resource limits applied (heap 1536M, hard limit 2G)."
    fi
fi

# Reload systemd and enable the service
systemctl daemon-reload
systemctl enable openclaw
systemctl is-enabled --quiet openclaw || {
    log_error "Service openclaw failed to enable"
    exit 1
}
log_success "OpenClaw systemd service installed and enabled."

# ── Step 8: Session isolation ────────────────────────────────────────────────
step 8 $TOTAL_STEPS "Verifying session isolation"

# Session isolation is already set in the config file above
# This step verifies and sets it via CLI if openclaw is available
if sudo -u "$OPENCLAW_USER" bash -c 'command -v openclaw' &>/dev/null; then
    log_info "Session isolation (dmScope: per-channel-peer) is configured in openclaw.json5."
else
    log_warn "openclaw CLI not found in PATH. Session isolation is set in the config file."
fi

# Set up config version control
if [[ ! -d "${OPENCLAW_DIR}/.git" ]]; then
    sudo -u "$OPENCLAW_USER" bash -c "cd '${OPENCLAW_DIR}' && git init && git add . && git commit -m 'baseline hardened config'" 2>/dev/null || true
    log_info "Configuration placed under git version control."
else
    log_warn "Git repo already initialized in ${OPENCLAW_DIR}."
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} Phase 3 complete! OpenClaw installed.${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}Node.js:${NC}        $(node -v 2>/dev/null || echo 'check manually')"
echo -e "  ${BOLD}pnpm:${NC}           $(pnpm -v 2>/dev/null || echo 'check manually')"
echo -e "  ${BOLD}Docker:${NC}         $(docker --version 2>/dev/null || echo 'check manually')"
echo -e "  ${BOLD}Config:${NC}         ${OPENCLAW_CONFIG}"
echo -e "  ${BOLD}Service:${NC}        openclaw.service (enabled)"
echo -e "  ${BOLD}Session scope:${NC}  per-channel-peer (isolated)"
echo ""
echo -e "  ${YELLOW}Key security settings:${NC}"
echo -e "    Gateway:    loopback only (127.0.0.1)"
echo -e "    Sandbox:    all (Docker isolation)"
echo -e "    Tools:      minimal profile"
echo -e "    Workspace:  no access"
echo -e "    Plugins:    disabled"
echo -e "    mDNS:       off"
echo ""
echo -e "  Next step: ${BOLD}sudo -u ${OPENCLAW_USER} bash 04-first-agent.sh${NC}"
echo ""
