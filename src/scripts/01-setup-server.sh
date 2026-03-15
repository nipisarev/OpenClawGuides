#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Phase 1 — Initial Server Setup
#
# What this script does:
#   1. Updates all system packages to the latest versions
#   2. Creates the "openclaw" user with sudo access
#   3. Sets up SSH key-based access for the new user
#   4. Installs essential utility packages
#   5. Configures the server timezone to UTC
#
# Run as root on a fresh Ubuntu 22.04+ or Debian 12+ server.
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TOTAL_STEPS=5
OPENCLAW_USER="openclaw"

check_root
check_ubuntu

print_banner
echo -e "${BOLD}Phase 1: Initial Server Setup${NC}"
echo ""

# ── Step 1: System update ────────────────────────────────────────────────────
step 1 $TOTAL_STEPS "Updating system packages"

wait_for_apt
log_info "Running apt update && apt upgrade -y (this may take a few minutes)..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
log_success "System packages updated."

# ── Step 2: Create openclaw user ─────────────────────────────────────────────
step 2 $TOTAL_STEPS "Creating user '${OPENCLAW_USER}'"

if id "$OPENCLAW_USER" &>/dev/null; then
    log_warn "User '${OPENCLAW_USER}' already exists — skipping creation."
else
    adduser --disabled-password --gecos "OpenClaw Service Account" "$OPENCLAW_USER"
    log_success "User '${OPENCLAW_USER}' created."
fi

# Ensure the user is in the sudo group
if groups "$OPENCLAW_USER" | grep -qw sudo; then
    log_warn "User '${OPENCLAW_USER}' is already in the sudo group."
else
    usermod -aG sudo "$OPENCLAW_USER"
    log_success "User '${OPENCLAW_USER}' added to the sudo group."
fi

# ── Step 3: Set up SSH authorized_keys ───────────────────────────────────────
step 3 $TOTAL_STEPS "Setting up SSH access for '${OPENCLAW_USER}'"

OPENCLAW_HOME=$(eval echo "~${OPENCLAW_USER}")
SSH_DIR="${OPENCLAW_HOME}/.ssh"

if [[ -f "${SSH_DIR}/authorized_keys" ]] && [[ -s "${SSH_DIR}/authorized_keys" ]]; then
    log_warn "SSH authorized_keys already exists for '${OPENCLAW_USER}' — skipping."
else
    # Copy from root if available, otherwise prompt
    if [[ -f /root/.ssh/authorized_keys ]] && [[ -s /root/.ssh/authorized_keys ]]; then
        mkdir -p "$SSH_DIR"
        cp /root/.ssh/authorized_keys "${SSH_DIR}/authorized_keys"
        log_info "Copied SSH keys from root to '${OPENCLAW_USER}'."
    else
        log_warn "No SSH keys found for root."
        SSH_KEY=$(prompt_input "Paste the SSH public key for '${OPENCLAW_USER}' (or leave empty to skip)")
        if [[ -n "$SSH_KEY" ]]; then
            mkdir -p "$SSH_DIR"
            echo "$SSH_KEY" > "${SSH_DIR}/authorized_keys"
            log_success "SSH public key added."
        else
            log_warn "No SSH key provided — you will need to set up access manually."
        fi
    fi

    # Fix ownership and permissions
    if [[ -d "$SSH_DIR" ]]; then
        chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        chmod 600 "${SSH_DIR}/authorized_keys" 2>/dev/null || true
        log_success "SSH directory permissions set (700/600)."
    fi

    if [[ ! -s "$OPENCLAW_HOME/.ssh/authorized_keys" ]]; then
        log_error "authorized_keys is empty after copy — SSH key setup failed"
        exit 1
    fi
    if ! grep -q "^ssh-" "$OPENCLAW_HOME/.ssh/authorized_keys" 2>/dev/null; then
        log_error "authorized_keys does not contain valid SSH public key lines"
        exit 1
    fi

    ssh-keygen -l -f "$OPENCLAW_HOME/.ssh/authorized_keys" &>/dev/null || {
        log_error "SSH key validation failed — keys may be corrupt"
        exit 1
    }
    log_success "SSH keys validated successfully"
fi

# ── Step 4: Install essential packages ───────────────────────────────────────
step 4 $TOTAL_STEPS "Installing essential packages"

ESSENTIAL_PKGS=(curl git wget jq unzip htop software-properties-common apt-transport-https ca-certificates gnupg lsb-release)
MISSING_PKGS=()

for pkg in "${ESSENTIAL_PKGS[@]}"; do
    if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [[ ${#MISSING_PKGS[@]} -eq 0 ]]; then
    log_warn "All essential packages are already installed."
else
    log_info "Installing: ${MISSING_PKGS[*]}"
    wait_for_apt
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${MISSING_PKGS[@]}"
    log_success "Essential packages installed."
fi

# ── Step 5: Configure timezone ───────────────────────────────────────────────
step 5 $TOTAL_STEPS "Configuring timezone to UTC"

CURRENT_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "unknown")
if [[ "$CURRENT_TZ" == "UTC" ]] || [[ "$CURRENT_TZ" == "Etc/UTC" ]]; then
    log_warn "Timezone is already set to UTC."
else
    timedatectl set-timezone UTC 2>/dev/null || ln -sf /usr/share/zoneinfo/UTC /etc/localtime
    log_success "Timezone set to UTC (was: ${CURRENT_TZ})."
fi

# ── Summary ──────────────────────────────────────────────────────────────────

log_warn "═══════════════════════════════════════════════════════"
log_warn "IMPORTANT: Test SSH login as 'openclaw' user NOW"
log_warn "  ssh openclaw@$(hostname -I | awk '{print $1}')"
log_warn "DO NOT proceed to Phase 2 until this works!"
log_warn "═══════════════════════════════════════════════════════"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} Phase 1 complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  User created:   ${BOLD}${OPENCLAW_USER}${NC}"
echo -e "  Timezone:        ${BOLD}UTC${NC}"
echo -e "  Next step:       ${BOLD}sudo bash 02-harden-server.sh${NC}"
echo ""
echo -e "  ${YELLOW}Tip:${NC} You can now SSH as '${OPENCLAW_USER}':"
echo -e "       ssh ${OPENCLAW_USER}@<your-server-ip>"
echo ""
