#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Phase 2 — Security Hardening
#
# What this script does:
#   1. Configures UFW firewall (deny all, allow SSH + Tailscale)
#   2. Installs and configures Fail2ban (bans after 5 failed SSH attempts)
#   3. Hardens SSH (disable root login, disable password auth, key-only)
#   4. Locks sshd_config with chattr +i to prevent tampering
#   5. Installs and enables unattended-upgrades for automatic security patches
#   6. Installs Tailscale VPN (your private tunnel to the server)
#
# Run as root on a server that completed Phase 1.
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TOTAL_STEPS=6
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"

check_root
check_ubuntu

setup_trap_handler
_SCRIPT_PHASE="hardening"

print_banner
echo -e "${BOLD}Phase 2: Security Hardening${NC}"
echo ""

# ── Step 1: UFW Firewall ─────────────────────────────────────────────────────
step 1 $TOTAL_STEPS "Configuring UFW firewall"

if ! is_installed ufw; then
    log_info "Installing UFW..."
    wait_for_apt
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw
fi

# Check current UFW status
UFW_STATUS=$(ufw status | head -1 || echo "inactive")

if echo "$UFW_STATUS" | grep -qi "active"; then
    log_warn "UFW is already active. Verifying rules..."
else
    log_info "Setting default policies: deny incoming, allow outgoing."
    ufw default deny incoming
    ufw default allow outgoing
fi

# Ensure SSH is allowed (critical — otherwise we lose access)
if ! ufw status | grep -q "22/tcp"; then
    ufw allow 22/tcp
    verify_ufw_rule "22/tcp" || { log_error "SSH rule not confirmed in UFW — aborting"; exit 1; }
    log_info "Allowed SSH (port 22/tcp)."
else
    log_warn "SSH (port 22/tcp) already allowed."
fi

# Allow Tailscale UDP port
if ! ufw status | grep -q "41641/udp"; then
    ufw allow 41641/udp
    log_info "Allowed Tailscale (port 41641/udp)."
else
    log_warn "Tailscale (port 41641/udp) already allowed."
fi

# Enable UFW if not active
if ! ufw status | grep -qi "Status: active"; then
    log_info "Enabling UFW..."
    echo "y" | ufw enable
    _UFW_ENABLED_BY_US=true
    verify_ufw_rule "22/tcp" || { log_error "SSH rule lost after UFW enable — disabling firewall"; ufw --force disable; exit 1; }
fi

log_success "UFW configured: deny incoming, allow SSH (22/tcp) + Tailscale (41641/udp)."

# ── Step 2: Fail2ban ─────────────────────────────────────────────────────────
step 2 $TOTAL_STEPS "Installing and configuring Fail2ban"

if is_installed fail2ban-client; then
    log_warn "Fail2ban is already installed."
else
    log_info "Installing Fail2ban..."
    wait_for_apt
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fail2ban
fi

# Deploy jail.local configuration
JAIL_LOCAL="/etc/fail2ban/jail.local"
if [[ -f "$JAIL_LOCAL" ]]; then
    log_warn "Fail2ban jail.local already exists — skipping overwrite."
else
    # Check if we have a config template in the repo
    JAIL_TEMPLATE="${SCRIPT_DIR}/../configs/fail2ban-jail.local"
    if [[ -f "$JAIL_TEMPLATE" ]]; then
        cp "$JAIL_TEMPLATE" "$JAIL_LOCAL"
        log_info "Deployed jail.local from template."
    else
        # Create inline — matches the guide's configuration
        cat > "$JAIL_LOCAL" << 'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
maxretry = 5
bantime = 3600
findtime = 600
EOF
        log_info "Created jail.local with SSH protection (5 retries, 1-hour ban)."
    fi
fi

# Enable and start Fail2ban
systemctl enable --now fail2ban 2>/dev/null || true
log_success "Fail2ban active — bans IP after 5 failed SSH login attempts."

# ── Step 3: SSH Hardening ────────────────────────────────────────────────────
step 3 $TOTAL_STEPS "Hardening SSH configuration"

SSHD_CONFIG="/etc/ssh/sshd_config"

# Remove immutable flag if previously set (so we can edit)
chattr -i "$SSHD_CONFIG" 2>/dev/null || true

backup_config /etc/ssh/sshd_config
_SSHD_MODIFIED=true

# Backup before changes
if [[ ! -f "${SSHD_CONFIG}.backup-openclaw" ]]; then
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup-openclaw"
    log_info "Backup created at ${SSHD_CONFIG}.backup-openclaw"
fi

sshd_set() {
    local key="$1"
    local value="$2"
    if grep -qE "^\s*#?\s*${key}\s" "$SSHD_CONFIG"; then
        sed -i "s/^\s*#*\s*${key}\s.*/${key} ${value}/" "$SSHD_CONFIG"
    else
        echo "${key} ${value}" >> "$SSHD_CONFIG"
    fi
}

# Disable root login via SSH
sshd_set "PermitRootLogin" "no"
log_info "SSH: root login disabled."

# Disable password authentication — key-only access
sshd_set "PasswordAuthentication" "no"
log_info "SSH: password authentication disabled."

# Ensure pubkey auth is enabled
sshd_set "PubkeyAuthentication" "yes"
log_info "SSH: public key authentication enabled."

# Disable challenge-response
sshd_set "ChallengeResponseAuthentication" "no"
sshd_set "KbdInteractiveAuthentication" "no"

# Validate configuration before restart
if sshd -t 2>/dev/null; then
    systemctl restart sshd
    log_warn "DO NOT close this terminal session until SSH access is verified"
    verify_ssh_access || {
        log_error "SSH access broken after config change — rolling back"
        restore_config /etc/ssh/sshd_config
        systemctl restart sshd
        exit 1
    }
    log_success "SSH access verified after config change"
    log_success "SSH hardened and restarted (key-only auth, no root login)."
else
    log_error "SSH config validation failed! Restoring backup..."
    cp "${SSHD_CONFIG}.backup-openclaw" "$SSHD_CONFIG"
    systemctl restart sshd
    exit 1
fi

# ── Step 4: Lock sshd_config ────────────────────────────────────────────────
step 4 $TOTAL_STEPS "Locking SSH configuration with chattr +i"

if lsattr "$SSHD_CONFIG" 2>/dev/null | grep -q "\-i\-"; then
    log_warn "sshd_config is already immutable."
else
    safe_chattr "$SSHD_CONFIG"
    log_success "sshd_config locked — cannot be modified without 'chattr -i' first."
fi

# Also lock root authorized_keys if it exists
if [[ -f /root/.ssh/authorized_keys ]]; then
    safe_chattr /root/.ssh/authorized_keys || log_warn "Could not lock root authorized_keys"
    log_info "root authorized_keys locked."
fi

# ── Step 5: Unattended upgrades ─────────────────────────────────────────────
step 5 $TOTAL_STEPS "Installing automatic security updates (unattended-upgrades)"

if dpkg -l unattended-upgrades 2>/dev/null | grep -q "^ii"; then
    log_warn "unattended-upgrades is already installed."
else
    wait_for_apt
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades
fi

# Enable unattended-upgrades non-interactively
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -plow unattended-upgrades 2>/dev/null || true

# Verify
if unattended-upgrade --dry-run 2>/dev/null; then
    log_success "Automatic security updates enabled and verified."
else
    log_warn "unattended-upgrade dry-run had issues — check /var/log/unattended-upgrades/."
fi

# ── Step 6: Tailscale VPN ───────────────────────────────────────────────────
step 6 $TOTAL_STEPS "Installing Tailscale VPN"

if is_installed tailscale; then
    log_warn "Tailscale is already installed."
    TS_STATUS=$(tailscale status 2>/dev/null || echo "not connected")
    if echo "$TS_STATUS" | grep -q "100\."; then
        TS_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
        log_warn "Tailscale is already connected. IP: ${TS_IP}"
    fi
else
    log_info "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    log_success "Tailscale installed."
fi

# Connect to Tailscale
TS_CONNECTED=false
if tailscale status &>/dev/null; then
    if tailscale ip -4 &>/dev/null; then
        TS_CONNECTED=true
    fi
fi

if [[ "$TS_CONNECTED" == "true" ]]; then
    TS_IP=$(tailscale ip -4)
    log_warn "Tailscale already connected. IP: ${TS_IP}"
elif [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
    log_info "Connecting to Tailscale with provided auth key..."
    tailscale up --authkey="$TAILSCALE_AUTH_KEY"
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || true)
    if [[ -z "$TAILSCALE_IP" ]]; then
        log_warn "Tailscale IP not assigned — VPN may not be fully connected"
    else
        if ping -c 1 -W 5 "$TAILSCALE_IP" &>/dev/null; then
            log_success "Tailscale connectivity verified (IP: $TAILSCALE_IP)"
        else
            log_warn "Tailscale IP assigned ($TAILSCALE_IP) but ping failed — check network"
        fi
    fi
    TS_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
    log_success "Tailscale connected. IP: ${TS_IP}"
else
    log_info "No TAILSCALE_AUTH_KEY provided."
    echo ""
    echo -e "  ${YELLOW}To connect Tailscale, run one of:${NC}"
    echo ""
    echo -e "    ${BOLD}sudo tailscale up${NC}                     # interactive (opens auth URL)"
    echo -e "    ${BOLD}sudo tailscale up --authkey=tskey-...${NC}  # non-interactive"
    echo ""
    echo -e "  Get an auth key at: ${BLUE}https://login.tailscale.com/admin/settings/keys${NC}"
    TS_IP="(not connected)"
fi

verify_ssh_access || log_warn "SSH access check failed at end of hardening — verify manually before closing this terminal!"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} Phase 2 complete! Server hardened.${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}Firewall:${NC}           UFW active — SSH + Tailscale only"
echo -e "  ${BOLD}Fail2ban:${NC}           Bans after 5 failed SSH attempts (1h)"
echo -e "  ${BOLD}SSH:${NC}                Key-only auth, root login disabled"
echo -e "  ${BOLD}sshd_config:${NC}        Locked (chattr +i)"
echo -e "  ${BOLD}Auto-updates:${NC}       Enabled (unattended-upgrades)"
echo -e "  ${BOLD}Tailscale IP:${NC}       ${TS_IP}"
echo ""
echo -e "  Next step: ${BOLD}sudo bash 03-install-openclaw.sh${NC}"
echo ""
