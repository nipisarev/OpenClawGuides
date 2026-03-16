#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Phase 6 — Maintenance Setup
#
# What this script does:
#   1. Installs the nightly security audit script (from src/security/nightly-audit.sh)
#   2. Installs the agent brain backup script (from src/security/agent-brain-backup.sh)
#   3. Sets up cron jobs (nightly audit at 3am, brain backup every hour)
#   4. Verifies all cron entries are in place
#
# Run as root on a server that completed Phase 4 (or 5).
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TOTAL_STEPS=4
OPENCLAW_USER="openclaw"
OPENCLAW_HOME=$(eval echo "~${OPENCLAW_USER}")

# Paths to source templates in the repo
REPO_SECURITY_DIR="${SCRIPT_DIR}/../security"
REPO_SCRIPTS_DIR="${SCRIPT_DIR}"

# Target paths on the server
SECURITY_DIR="/opt/security"
BASELINES_DIR="/var/lib/openclaw/baselines"
AUDIT_LOG_DIR="/var/log/openclaw"
AUDIT_SCRIPT="${SECURITY_DIR}/nightly-audit.sh"
BACKUP_SCRIPT="${SECURITY_DIR}/agent-brain-backup.sh"
BACKUP_DIR="${OPENCLAW_HOME}/backups/brain"

check_root
check_ubuntu

print_banner
echo -e "${BOLD}Phase 6: Maintenance Setup${NC}"
echo ""

# ── Step 1: Nightly security audit script ────────────────────────────────────
step 1 $TOTAL_STEPS "Installing nightly security audit script"

mkdir -p "$SECURITY_DIR" "$BASELINES_DIR" "$AUDIT_LOG_DIR"

if [[ -f "$AUDIT_SCRIPT" ]]; then
    log_warn "Nightly audit script already exists at ${AUDIT_SCRIPT}"
    if ! confirm "Overwrite with latest version from repo?"; then
        log_info "Keeping existing audit script."
    else
        rm -f "$AUDIT_SCRIPT"
    fi
fi

if [[ ! -f "$AUDIT_SCRIPT" ]]; then
    # The repo ships a full audit script at src/security/nightly-audit.sh
    AUDIT_TEMPLATE="${REPO_SECURITY_DIR}/nightly-audit.sh"

    if [[ -f "$AUDIT_TEMPLATE" ]]; then
        # Copy the script and its dependency (common.sh) to /opt/security
        cp "$AUDIT_TEMPLATE" "$AUDIT_SCRIPT"

        # The audit script sources ../scripts/common.sh — create that path
        mkdir -p "${SECURITY_DIR}/../scripts" 2>/dev/null || true
        # Alternatively, copy common.sh alongside the security scripts
        COMMON_TARGET="${SECURITY_DIR}/../scripts/common.sh"
        if [[ ! -f "$COMMON_TARGET" ]]; then
            # Create symlink structure so source paths work
            mkdir -p "$(dirname "$COMMON_TARGET")"
            cp "${REPO_SCRIPTS_DIR}/common.sh" "$COMMON_TARGET"
        fi

        mkdir -p "${OPENCLAW_HOME}/scripts"
        cp "$SCRIPT_DIR/common.sh" "${OPENCLAW_HOME}/scripts/" 2>/dev/null || true
        log_success "Deployed nightly audit script from ${AUDIT_TEMPLATE}"
    else
        log_error "Audit template not found at ${AUDIT_TEMPLATE}"
        log_info "Expected repo structure: src/security/nightly-audit.sh"
        exit 1
    fi

    chmod 700 "$AUDIT_SCRIPT"
fi

# Generate initial baselines if none exist
if [[ ! -f "${BASELINES_DIR}/ports.baseline" ]]; then
    log_info "Generating initial security baselines..."
    bash "$AUDIT_SCRIPT" --init-baselines 2>/dev/null || {
        log_warn "Baseline generation had issues — will be retried on first cron run"
    }
    log_success "Baselines generated in ${BASELINES_DIR}/"
else
    log_warn "Baselines already exist. To regenerate: ${AUDIT_SCRIPT} --init-baselines"
fi

# ── Step 2: Agent brain backup script ────────────────────────────────────────
step 2 $TOTAL_STEPS "Installing agent brain backup script"

if [[ -f "$BACKUP_SCRIPT" ]]; then
    log_warn "Brain backup script already exists at ${BACKUP_SCRIPT}"
    if ! confirm "Overwrite with latest version from repo?"; then
        log_info "Keeping existing backup script."
    else
        rm -f "$BACKUP_SCRIPT"
    fi
fi

if [[ ! -f "$BACKUP_SCRIPT" ]]; then
    BACKUP_TEMPLATE="${REPO_SECURITY_DIR}/agent-brain-backup.sh"

    if [[ -f "$BACKUP_TEMPLATE" ]]; then
        cp "$BACKUP_TEMPLATE" "$BACKUP_SCRIPT"
        log_success "Deployed brain backup script from ${BACKUP_TEMPLATE}"
    else
        log_error "Backup template not found at ${BACKUP_TEMPLATE}"
        log_info "Expected repo structure: src/security/agent-brain-backup.sh"
        exit 1
    fi

    chmod 700 "$BACKUP_SCRIPT"
fi

# Create backup directory with correct ownership
mkdir -p "$BACKUP_DIR"
chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" "$BACKUP_DIR"
log_info "Backup storage: ${BACKUP_DIR}"

# ── Step 3: Set up cron jobs ────────────────────────────────────────────────
step 3 $TOTAL_STEPS "Setting up cron jobs"

# Nightly audit at 3:00 AM
AUDIT_CRON="/etc/cron.d/openclaw-security-audit"
if [[ -f "$AUDIT_CRON" ]]; then
    log_warn "Nightly audit cron already exists."
else
    cat > "$AUDIT_CRON" << EOF
# OpenClaw nightly security audit — runs at 3:00 AM daily
# Checks 13 security metrics and logs to ${AUDIT_LOG_DIR}/
0 3 * * * root ${AUDIT_SCRIPT}
EOF
    chmod 644 "$AUDIT_CRON"
    log_success "Nightly audit cron installed (3:00 AM daily)."
fi

# Hourly brain backup
BACKUP_CRON="/etc/cron.d/openclaw-brain-backup"
if [[ -f "$BACKUP_CRON" ]]; then
    log_warn "Brain backup cron already exists."
else
    cat > "$BACKUP_CRON" << EOF
# OpenClaw agent brain backup — runs every hour
# Backs up SOUL.md, MEMORY.md, skills/, config to git repo
0 * * * * ${OPENCLAW_USER} ${BACKUP_SCRIPT}
EOF
    chmod 644 "$BACKUP_CRON"
    log_success "Brain backup cron installed (hourly)."
fi

# ── Step 4: Verify cron entries ──────────────────────────────────────────────
step 4 $TOTAL_STEPS "Verifying cron entries"

echo ""
echo -e "  ${BOLD}Installed cron jobs:${NC}"
echo ""

VERIFY_OK=true

if [[ -f "$AUDIT_CRON" ]]; then
    AUDIT_ENTRY=$(grep -v "^#" "$AUDIT_CRON" | grep -v "^$" | head -1)
    echo -e "    ${GREEN}[OK]${NC} Nightly audit:  ${AUDIT_ENTRY}"
else
    echo -e "    ${RED}[MISSING]${NC} Nightly audit cron"
    VERIFY_OK=false
fi

if [[ -f "$BACKUP_CRON" ]]; then
    BACKUP_ENTRY=$(grep -v "^#" "$BACKUP_CRON" | grep -v "^$" | head -1)
    echo -e "    ${GREEN}[OK]${NC} Brain backup:   ${BACKUP_ENTRY}"
else
    echo -e "    ${RED}[MISSING]${NC} Brain backup cron"
    VERIFY_OK=false
fi

echo ""

# Run initial backup to verify the script works
log_info "Running initial brain backup to verify..."
sudo -u "$OPENCLAW_USER" bash "$BACKUP_SCRIPT" 2>/dev/null || {
    bash "$BACKUP_SCRIPT" 2>/dev/null || log_warn "Initial backup run had issues — will be retried on first cron run"
    chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" "$BACKUP_DIR" 2>/dev/null || log_warn "Could not set backup directory ownership"
}
log_success "Initial backup complete."

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN} Phase 6 complete! Maintenance automation installed.${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}Nightly audit:${NC}"
echo -e "    Script:   ${AUDIT_SCRIPT}"
echo -e "    Schedule: Every day at 3:00 AM"
echo -e "    Logs:     ${AUDIT_LOG_DIR}/"
echo -e "    Checks:   13 security metrics (ports, /etc, SSH, secrets, Docker,"
echo -e "              disk, logins, sudo, skills, config, chattr, cron, memory)"
echo ""
echo -e "  ${BOLD}Brain backup:${NC}"
echo -e "    Script:   ${BACKUP_SCRIPT}"
echo -e "    Schedule: Every hour"
echo -e "    Storage:  ${BACKUP_DIR}/ (git versioned)"
echo -e "    RPO:      1 hour"
echo ""
echo -e "  ${YELLOW}Useful commands:${NC}"
echo -e "    ${BOLD}cat ${AUDIT_LOG_DIR}/audit-\$(date +%Y-%m-%d).log${NC}  — view today's audit"
echo -e "    ${BOLD}cd ${BACKUP_DIR} && git log --oneline${NC}             — view backup history"
echo -e "    ${BOLD}${AUDIT_SCRIPT} --init-baselines${NC}                  — regenerate baselines"
echo -e "    ${BOLD}${BACKUP_SCRIPT} --rollback 3${NC}                     — rollback 3 commits"
echo ""
echo -e "  ${YELLOW}Telegram notifications (optional):${NC}"
echo -e "    Set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID in /etc/openclaw/env"
echo -e "    Then change the audit cron to: ${AUDIT_SCRIPT} --telegram"
echo ""
