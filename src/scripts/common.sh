#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# common.sh — Shared utility functions for OpenClaw installation scripts
# Source this file from other scripts: source "$(dirname "$0")/common.sh"
# ──────────────────────────────────────────────────────────────────────────────

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Logging ───────────────────────────────────────────────────────────────────
# Usage: log_info "Installing packages..."
#        log_success "Done."
#        log_warn "Skipping — already configured."
#        log_error "Failed to install Docker."

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# ── Step progress indicator ───────────────────────────────────────────────────
# Usage: step 1 5 "Updating system packages"
step() {
    local current="$1"
    local total="$2"
    shift 2
    echo -e "\n${BOLD}${BLUE}[${current}/${total}]${NC} ${BOLD}$*${NC}"
}

# ── Root check ────────────────────────────────────────────────────────────────
# Exits with an error if the current user is not root.
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)."
        exit 1
    fi
}

# ── OS check ──────────────────────────────────────────────────────────────────
# Exits if the OS is not Ubuntu 22.04+ or Debian 12+.
# Sets global variables: OS_ID, OS_VERSION_ID, OS_CODENAME
check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS — /etc/os-release not found."
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
                log_error "Ubuntu ${OS_VERSION_ID} detected. Minimum required: 22.04."
                exit 1
            fi
            ;;
        debian)
            if [[ "${OS_VERSION_ID%%.*}" -lt 12 ]]; then
                log_error "Debian ${OS_VERSION_ID} detected. Minimum required: 12."
                exit 1
            fi
            ;;
        *)
            log_error "Unsupported OS: ${OS_ID}. Only Ubuntu 22.04+ and Debian 12+ are supported."
            exit 1
            ;;
    esac

    log_info "Detected ${OS_ID} ${OS_VERSION_ID} (${OS_CODENAME})"
}

# ── Command existence check ──────────────────────────────────────────────────
# Usage: if is_installed docker; then ... fi
is_installed() {
    command -v "$1" &>/dev/null
}

# ── Prompt with default ──────────────────────────────────────────────────────
# Usage: result=$(prompt_input "Enter hostname" "openclaw")
prompt_input() {
    local prompt_text="$1"
    local default_value="${2:-}"
    local result

    if [[ -n "$default_value" ]]; then
        read -rp "$(echo -e "${BLUE}?${NC} ${prompt_text} [${default_value}]: ")" result < /dev/tty
        echo "${result:-$default_value}"
    else
        read -rp "$(echo -e "${BLUE}?${NC} ${prompt_text}: ")" result < /dev/tty
        echo "$result"
    fi
}

# ── Yes/No confirmation ──────────────────────────────────────────────────────
# Usage: if confirm "Proceed with installation?"; then ... fi
#        if confirm "Enable feature?" "n"; then ... fi  # default No
confirm() {
    local prompt_text="$1"
    local default="${2:-y}"
    local yn_hint

    if [[ "$default" == "y" ]]; then
        yn_hint="Y/n"
    else
        yn_hint="y/N"
    fi

    local answer
    read -rp "$(echo -e "${YELLOW}?${NC} ${prompt_text} [${yn_hint}]: ")" answer < /dev/tty
    answer="${answer:-$default}"

    case "${answer,,}" in
        y|yes) return 0 ;;
        *)     return 1 ;;
    esac
}

# ── Wait for apt lock ────────────────────────────────────────────────────────
# Sometimes another process holds the apt lock. Wait up to 60s.
wait_for_apt() {
    local retries=12
    while fuser /var/lib/dpkg/lock-frontend &>/dev/null 2>&1; do
        if (( retries-- <= 0 )); then
            log_error "Timed out waiting for apt lock."
            exit 1
        fi
        log_warn "Waiting for apt lock to be released..."
        sleep 5
    done
}

# ── Banner ────────────────────────────────────────────────────────────────────
print_banner() {
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
    echo -e "  ${BOLD}Hardened VPS Setup${NC} — Self-hosted AI Assistant"
    echo ""
}

# ── Global state (for trap handler) ──────────────────────────────────────────
_UFW_ENABLED_BY_US=false
_SSHD_MODIFIED=false
_CHATTR_FILES=()
_SCRIPT_PHASE=""
_CLEANUP_DONE=false

# ── Safety functions ─────────────────────────────────────────────────────────

backup_config() {
    local file="$1"
    local backup="${file}.backup-openclaw-$(date +%Y%m%d-%H%M%S)"

    cp -a "$file" "$backup"
    log_info "Backed up ${file} -> ${backup}"

    local old_backups
    old_backups=$(ls -1t "${file}.backup-openclaw-"* 2>/dev/null | tail -n +4)
    if [[ -n "$old_backups" ]]; then
        echo "$old_backups" | while read -r f; do
            rm -f "$f"
            log_info "Removed old backup: ${f}"
        done
    fi
}

restore_config() {
    local file="$1"
    local latest
    latest=$(ls -1t "${file}.backup-openclaw-"* 2>/dev/null | head -n 1)

    if [[ -z "$latest" ]]; then
        log_error "No backup found for ${file}"
        return 1
    fi

    cp -a "$latest" "$file"
    log_success "Restored ${file} from ${latest}"
}

verify_ssh_access() {
    local port="${1:-22}"
    local attempt=1

    while (( attempt <= 3 )); do
        # Check 1: Is the SSH service running?
        local svc="${SSH_SERVICE:-ssh}"
        if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
            log_warn "SSH service '${svc}' not active (attempt ${attempt}/3)"
            sleep 2
            attempt=$((attempt + 1))
            continue
        fi

        # Check 2: Is sshd actually listening on the port?
        if ss -tlnp 2>/dev/null | grep -q ":${port}[[:space:]]"; then
            # Check 3: Is the config valid?
            if sshd -t 2>/dev/null; then
                log_success "SSH access verified (service active, listening on port ${port}, config valid)"
                return 0
            else
                log_error "SSH config validation failed (sshd -t)"
                return 1
            fi
        fi

        log_warn "SSH not yet listening on port ${port} (attempt ${attempt}/3)"
        sleep 2
        attempt=$((attempt + 1))
    done

    log_error "SSH not listening on port ${port} after 3 attempts"
    return 1
}

verify_ufw_rule() {
    local rule="$1"
    local port="${rule%%/*}"

    # Check multiple output formats: "22/tcp", "22", "OpenSSH", port in numbered list
    if ufw status | grep -qE "(^${port}(/tcp|/udp)?[[:space:]]|OpenSSH|^SSH[[:space:]])"; then
        log_success "UFW rule confirmed: ${rule}"
        return 0
    fi

    # Fallback: check ufw show added for raw rules
    if ufw show added 2>/dev/null | grep -q "${port}"; then
        log_success "UFW rule confirmed (via show added): ${rule}"
        return 0
    fi

    log_error "UFW rule NOT found: ${rule}"
    return 1
}

verify_service() {
    local service="$1"
    local attempt=1

    while (( attempt <= 5 )); do
        if systemctl is-active --quiet "$service"; then
            log_success "Service ${service} is active (attempt ${attempt}/5)"
            return 0
        fi
        log_warn "Service ${service} not active yet (attempt ${attempt}/5), retrying..."
        sleep 2
        (( attempt++ ))
    done

    log_error "Service ${service} failed to become active after 5 attempts"
    return 1
}

safe_chattr() {
    local file="$1"

    if [[ "$file" == *sshd_config* ]]; then
        if ! sshd -t 2>/dev/null; then
            log_error "sshd config validation failed — refusing to lock ${file}"
            return 1
        fi
    fi

    if [[ "$file" == *authorized_keys* ]]; then
        if ! ssh-keygen -l -f "$file" >/dev/null 2>&1; then
            log_error "SSH key validation failed — refusing to lock ${file}"
            return 1
        fi
    fi

    chattr +i "$file"
    _CHATTR_FILES+=("$file")
    log_success "Locked ${file} (chattr +i)"
}

setup_trap_handler() {
    _cleanup_on_failure() {
        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            return
        fi

        if [[ "${_CLEANUP_DONE:-false}" == true ]]; then return; fi
        _CLEANUP_DONE=true

        log_warn "Script failed (exit code ${exit_code}) — starting rollback..."

        if [[ ${#_CHATTR_FILES[@]} -gt 0 ]]; then
            for f in "${_CHATTR_FILES[@]}"; do
                chattr -i "$f" 2>/dev/null && log_info "Unlocked ${f} (chattr -i)"
            done
        fi

        if [[ "$_SSHD_MODIFIED" == true ]]; then
            log_info "Restoring sshd_config..."
            restore_config /etc/ssh/sshd_config && {
                local svc="${SSH_SERVICE:-ssh}"
                systemctl restart "$svc" 2>/dev/null || systemctl restart sshd 2>/dev/null
            }
        fi

        if [[ "$_UFW_ENABLED_BY_US" == true ]]; then
            log_info "Disabling UFW..."
            ufw --force disable
        fi

        log_warn "Rollback complete"
    }

    trap _cleanup_on_failure EXIT ERR
}
