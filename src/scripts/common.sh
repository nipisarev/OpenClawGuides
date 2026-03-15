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
        read -rp "$(echo -e "${BLUE}?${NC} ${prompt_text} [${default_value}]: ")" result
        echo "${result:-$default_value}"
    else
        read -rp "$(echo -e "${BLUE}?${NC} ${prompt_text}: ")" result
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
    read -rp "$(echo -e "${YELLOW}?${NC} ${prompt_text} [${yn_hint}]: ")" answer
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
