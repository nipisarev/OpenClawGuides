#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# agent-brain-backup.sh — Git-based agent brain/memory backup
#
# Backs up agent SOUL.md, MEMORY.md, skills/, and config to a git repository.
# Supports rollback to a previous state.
#
# Usage:
#   ./agent-brain-backup.sh                Auto-commit current state
#   ./agent-brain-backup.sh --rollback 3   Restore state from 3 commits ago
#
# Install cron (hourly backup):
#   echo "0 * * * * /opt/security/agent-brain-backup.sh" | crontab -
#
# RPO (Recovery Point Objective): 1 hour
#
# Reference: SlowMist OpenClaw Security Practice Guide
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/common.sh
source "${SCRIPT_DIR}/../scripts/common.sh"

# ── Configuration ────────────────────────────────────────────────────────────
OPENCLAW_WORKSPACE="${OPENCLAW_WORKSPACE:-/home/openclaw/openclaw/workspace}"
OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-/home/openclaw/.openclaw}"
BACKUP_DIR="${BACKUP_DIR:-/home/openclaw/backups/brain}"
ROLLBACK_COUNT=""

# Files and directories to back up
BACKUP_TARGETS=(
    "SOUL.md"
    "MEMORY.md"
    "IDENTITY.md"
    "skills/"
)
CONFIG_TARGETS=(
    "openclaw.json"
    "openclaw.json5"
)

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --rollback)
            if [[ -z "${2:-}" || ! "$2" =~ ^[0-9]+$ ]]; then
                log_error "Usage: --rollback N (number of commits to go back)"
                exit 1
            fi
            ROLLBACK_COUNT="$2"
            shift 2
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# ── Initialize backup repo ──────────────────────────────────────────────────
init_backup_repo() {
    if [[ ! -d "${BACKUP_DIR}/.git" ]]; then
        log_info "Initializing backup repository at ${BACKUP_DIR}"
        mkdir -p "$BACKUP_DIR"
        git -C "$BACKUP_DIR" init
        git -C "$BACKUP_DIR" config user.email "openclaw-backup@localhost"
        git -C "$BACKUP_DIR" config user.name "OpenClaw Backup"
        log_success "Backup repository initialized"
    fi
}

# ── Backup mode ──────────────────────────────────────────────────────────────
do_backup() {
    init_backup_repo

    local changed=false

    # Copy workspace files
    for target in "${BACKUP_TARGETS[@]}"; do
        local src="${OPENCLAW_WORKSPACE}/${target}"
        local dst="${BACKUP_DIR}/${target}"

        if [[ -e "$src" ]]; then
            if [[ -d "$src" ]]; then
                mkdir -p "$dst"
                rsync -a --delete "$src" "$(dirname "$dst")/" 2>/dev/null && changed=true
            else
                mkdir -p "$(dirname "$dst")"
                cp -p "$src" "$dst" 2>/dev/null && changed=true
            fi
        fi
    done

    # Copy config files
    for target in "${CONFIG_TARGETS[@]}"; do
        local src="${OPENCLAW_CONFIG_DIR}/${target}"
        local dst="${BACKUP_DIR}/config/${target}"

        if [[ -f "$src" ]]; then
            mkdir -p "$(dirname "$dst")"
            cp -p "$src" "$dst" 2>/dev/null && changed=true
        fi
    done

    # Also back up crontab
    local crontab_file="${BACKUP_DIR}/config/crontab.bak"
    mkdir -p "$(dirname "$crontab_file")"
    crontab -l > "$crontab_file" 2>/dev/null || true

    # Commit if there are changes
    cd "$BACKUP_DIR"
    git add -A

    if git diff --cached --quiet 2>/dev/null; then
        log_info "No changes detected, skipping commit"
        return 0
    fi

    local timestamp
    timestamp=$(date +%Y-%m-%d_%H:%M:%S)
    git commit -m "auto-backup ${timestamp}" --quiet
    log_success "Backup committed: auto-backup ${timestamp}"

    # Push to remote if configured
    if git remote get-url origin &>/dev/null; then
        if git push origin main --quiet 2>/dev/null || git push origin master --quiet 2>/dev/null; then
            log_success "Backup pushed to remote"
        else
            log_warn "Failed to push to remote — backup saved locally"
        fi
    else
        log_info "No remote configured. To enable remote backup: git -C ${BACKUP_DIR} remote add origin <your-repo-url>"
    fi
}

# ── Rollback mode ────────────────────────────────────────────────────────────
do_rollback() {
    local n="$1"

    if [[ ! -d "${BACKUP_DIR}/.git" ]]; then
        log_error "No backup repository found at ${BACKUP_DIR}"
        exit 1
    fi

    cd "$BACKUP_DIR"

    # Verify the target commit exists
    local target_commit
    target_commit=$(git rev-parse "HEAD~${n}" 2>/dev/null) || {
        log_error "Cannot go back ${n} commits — not enough history"
        log_info "Available commits:"
        git log --oneline | head -20
        exit 1
    }

    local target_date
    target_date=$(git log -1 --format="%ci" "$target_commit")
    log_info "Rolling back to commit ${target_commit:0:8} (${target_date})"

    # Restore workspace files
    for target in "${BACKUP_TARGETS[@]}"; do
        local src="${BACKUP_DIR}/${target}"
        local dst="${OPENCLAW_WORKSPACE}/${target}"

        # Checkout the file/dir from the target commit
        git checkout "$target_commit" -- "$target" 2>/dev/null || {
            log_warn "File '${target}' not found in commit ${target_commit:0:8}, skipping"
            continue
        }

        if [[ -e "$src" ]]; then
            if [[ -d "$src" ]]; then
                mkdir -p "$dst"
                rsync -a --delete "$src" "$(dirname "$dst")/"
            else
                mkdir -p "$(dirname "$dst")"
                cp -p "$src" "$dst"
            fi
            log_success "Restored: ${target}"
        fi
    done

    # Restore config files
    for target in "${CONFIG_TARGETS[@]}"; do
        local src="${BACKUP_DIR}/config/${target}"
        local dst="${OPENCLAW_CONFIG_DIR}/${target}"

        git checkout "$target_commit" -- "config/${target}" 2>/dev/null || continue

        if [[ -f "$src" ]]; then
            mkdir -p "$(dirname "$dst")"
            cp -p "$src" "$dst"
            log_success "Restored config: ${target}"
        fi
    done

    # Reset the backup repo working tree back to HEAD
    git checkout HEAD -- . 2>/dev/null || true

    log_success "Rollback complete. Restart OpenClaw to apply: sudo systemctl restart openclaw"
}

# ── Main ─────────────────────────────────────────────────────────────────────
if [[ -n "${ROLLBACK_COUNT}" ]]; then
    do_rollback "$ROLLBACK_COUNT"
else
    do_backup
fi
