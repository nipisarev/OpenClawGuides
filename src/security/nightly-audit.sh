#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# nightly-audit.sh — 13-metric nightly security audit for OpenClaw VPS
#
# Usage:
#   ./nightly-audit.sh                   Run audit and report deviations
#   ./nightly-audit.sh --init-baselines  Create initial baselines
#   ./nightly-audit.sh --telegram        Send alerts via Telegram bot
#
# Install cron:
#   echo "0 3 * * * /opt/security/nightly-audit.sh --telegram" | crontab -
#
# Reference: SlowMist OpenClaw Security Practice Guide
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/common.sh
source "${SCRIPT_DIR}/../scripts/common.sh"

# ── Configuration ────────────────────────────────────────────────────────────
BASELINE_DIR="/var/lib/openclaw/baselines"
LOG_DIR="/var/log/openclaw"
REPORT_FILE="${LOG_DIR}/audit-$(date +%Y-%m-%d).log"
OPENCLAW_USER="${OPENCLAW_USER:-openclaw}"
OPENCLAW_HOME="${OPENCLAW_HOME:-/home/${OPENCLAW_USER}}"
OPENCLAW_DIR="${OPENCLAW_DIR:-/opt/openclaw}"

INIT_BASELINES=false
SEND_TELEGRAM=false
ALERT_COUNT=0
PASS_COUNT=0

# ── Parse arguments ──────────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --init-baselines) INIT_BASELINES=true ;;
        --telegram)       SEND_TELEGRAM=true ;;
        *)                log_error "Unknown argument: $arg"; exit 1 ;;
    esac
done

# ── Setup ────────────────────────────────────────────────────────────────────
mkdir -p "$BASELINE_DIR" "$LOG_DIR"

alert() {
    local metric="$1"
    local message="$2"
    ALERT_COUNT=$((ALERT_COUNT + 1))
    log_error "[ALERT] ${metric}: ${message}"
    echo "[ALERT] ${metric}: ${message}" >> "$REPORT_FILE"
}

pass() {
    local metric="$1"
    PASS_COUNT=$((PASS_COUNT + 1))
    log_success "[PASS] ${metric}"
    echo "[PASS] ${metric}" >> "$REPORT_FILE"
}

save_baseline() {
    local name="$1"
    local content="$2"
    echo "$content" > "${BASELINE_DIR}/${name}.baseline"
}

load_baseline() {
    local name="$1"
    local baseline_file="${BASELINE_DIR}/${name}.baseline"
    if [[ -f "$baseline_file" ]]; then
        cat "$baseline_file"
    else
        echo ""
    fi
}

send_telegram_alert() {
    local bot_token="${TELEGRAM_BOT_TOKEN:-}"
    local chat_id="${TELEGRAM_CHAT_ID:-}"

    if [[ -z "$bot_token" || -z "$chat_id" ]]; then
        log_warn "TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set, skipping Telegram notification"
        return 0
    fi

    local text
    text=$(cat "$REPORT_FILE")
    local hostname
    hostname=$(hostname)

    local payload
    payload=$(printf '{"chat_id":"%s","text":"🔒 Security Audit [%s]\\n\\nAlerts: %d | Passed: %d\\n\\n%s","parse_mode":""}' \
        "$chat_id" "$hostname" "$ALERT_COUNT" "$PASS_COUNT" "$text")

    curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$payload" > /dev/null 2>&1 || log_warn "Failed to send Telegram notification"
}

# ── Report header ────────────────────────────────────────────────────────────
{
    echo "=============================================="
    echo " OpenClaw Nightly Security Audit"
    echo " Host: $(hostname)"
    echo " Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "=============================================="
    echo ""
} > "$REPORT_FILE"

# ── Init baselines mode ─────────────────────────────────────────────────────
if [[ "$INIT_BASELINES" == "true" ]]; then
    log_info "Initializing baselines..."

    # SUID binaries
    suid_list=$(find / -perm -4000 -type f 2>/dev/null | sort)
    save_baseline "suid" "$suid_list"
    log_success "Baseline saved: SUID binaries ($(echo "$suid_list" | wc -l | tr -d ' ') files)"

    # Listening ports
    ports_list=$(ss -tlnp 2>/dev/null | tail -n +2 | awk '{print $4}' | sort)
    save_baseline "ports" "$ports_list"
    log_success "Baseline saved: listening ports"

    # chattr immutable files
    chattr_list=$(lsattr -R /etc/ssh/ /root/.ssh/ 2>/dev/null | grep -- '----i' | awk '{print $2}' | sort || true)
    save_baseline "chattr" "$chattr_list"
    log_success "Baseline saved: chattr immutable files"

    log_success "All baselines initialized in ${BASELINE_DIR}"
    exit 0
fi

# ── Check 1: SUID binaries ──────────────────────────────────────────────────
log_info "Check 1/13: SUID binaries"
current_suid=$(find / -perm -4000 -type f 2>/dev/null | sort)
baseline_suid=$(load_baseline "suid")

if [[ -z "$baseline_suid" ]]; then
    alert "SUID binaries" "No baseline found. Run with --init-baselines first."
elif [[ "$current_suid" != "$baseline_suid" ]]; then
    new_suid=$(comm -13 <(echo "$baseline_suid") <(echo "$current_suid") || true)
    if [[ -n "$new_suid" ]]; then
        alert "SUID binaries" "New SUID files detected: ${new_suid}"
    else
        pass "SUID binaries"
    fi
else
    pass "SUID binaries"
fi

# ── Check 2: Listening ports ────────────────────────────────────────────────
log_info "Check 2/13: Listening ports"
current_ports=$(ss -tlnp 2>/dev/null | tail -n +2 | awk '{print $4}' | sort)
baseline_ports=$(load_baseline "ports")

if [[ -z "$baseline_ports" ]]; then
    alert "Listening ports" "No baseline found. Run with --init-baselines first."
elif [[ "$current_ports" != "$baseline_ports" ]]; then
    new_ports=$(comm -13 <(echo "$baseline_ports") <(echo "$current_ports") || true)
    if [[ -n "$new_ports" ]]; then
        alert "Listening ports" "New ports detected: ${new_ports}"
    else
        pass "Listening ports"
    fi
else
    pass "Listening ports"
fi

# ── Check 3: Failed SSH logins ──────────────────────────────────────────────
log_info "Check 3/13: Failed SSH logins"
failed_ssh=0
if [[ -f /var/log/auth.log ]]; then
    failed_ssh=$(grep -c "Failed password\|Failed publickey" /var/log/auth.log 2>/dev/null || echo "0")
fi

if [[ "$failed_ssh" -gt 50 ]]; then
    alert "Failed SSH logins" "${failed_ssh} failed attempts in auth.log"
else
    pass "Failed SSH logins (${failed_ssh} attempts)"
fi

# ── Check 4: Open file descriptors ──────────────────────────────────────────
log_info "Check 4/13: Open file descriptors"
openclaw_pid=$(pgrep -f "openclaw gateway" 2>/dev/null | head -1 || true)

if [[ -n "$openclaw_pid" ]]; then
    fd_count=$(ls -1 /proc/"${openclaw_pid}"/fd 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$fd_count" -gt 1000 ]]; then
        alert "Open file descriptors" "OpenClaw process has ${fd_count} open FDs (threshold: 1000)"
    else
        pass "Open file descriptors (${fd_count})"
    fi
else
    log_warn "OpenClaw process not found, skipping FD check"
    echo "[SKIP] Open file descriptors — process not running" >> "$REPORT_FILE"
fi

# ── Check 5: Disk usage ─────────────────────────────────────────────────────
log_info "Check 5/13: Disk usage"
disk_pct=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')

if [[ "$disk_pct" -gt 85 ]]; then
    alert "Disk usage" "Root partition at ${disk_pct}% (threshold: 85%)"
else
    pass "Disk usage (${disk_pct}%)"
fi

# ── Check 6: Memory usage ───────────────────────────────────────────────────
log_info "Check 6/13: Memory usage"
mem_pct=$(free 2>/dev/null | awk '/^Mem:/{printf "%.0f", $3/$2 * 100}' || echo "0")

if [[ "$mem_pct" -gt 90 ]]; then
    alert "Memory usage" "Memory at ${mem_pct}% (threshold: 90%)"
else
    pass "Memory usage (${mem_pct}%)"
fi

# ── Check 7: Zombie processes ────────────────────────────────────────────────
log_info "Check 7/13: Zombie processes"
zombie_count=$(ps aux 2>/dev/null | awk '$8 ~ /Z/' | wc -l | tr -d ' ')

if [[ "$zombie_count" -gt 0 ]]; then
    alert "Zombie processes" "${zombie_count} zombie processes found"
else
    pass "Zombie processes"
fi

# ── Check 8: unattended-upgrades status ──────────────────────────────────────
log_info "Check 8/13: unattended-upgrades status"
if systemctl is-active --quiet unattended-upgrades 2>/dev/null; then
    pass "unattended-upgrades active"
else
    alert "unattended-upgrades" "Service is not active"
fi

# ── Check 9: Fail2ban status ────────────────────────────────────────────────
log_info "Check 9/13: Fail2ban status"
if systemctl is-active --quiet fail2ban 2>/dev/null; then
    banned=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $NF}' || echo "0")
    pass "Fail2ban active (${banned} currently banned)"
else
    alert "Fail2ban" "Service is not active"
fi

# ── Check 10: chattr immutable files ─────────────────────────────────────────
log_info "Check 10/13: chattr immutable files"
current_chattr=$(lsattr -R /etc/ssh/ /root/.ssh/ 2>/dev/null | grep -- '----i' | awk '{print $2}' | sort || true)
baseline_chattr=$(load_baseline "chattr")

if [[ -z "$baseline_chattr" ]]; then
    if [[ -z "$current_chattr" ]]; then
        alert "chattr files" "No immutable files found — expected SSHD config and authorized_keys to be immutable"
    else
        pass "chattr immutable files"
    fi
elif [[ "$current_chattr" != "$baseline_chattr" ]]; then
    removed=$(comm -23 <(echo "$baseline_chattr") <(echo "$current_chattr") || true)
    if [[ -n "$removed" ]]; then
        alert "chattr files" "Immutable attribute removed from: ${removed}"
    else
        pass "chattr immutable files"
    fi
else
    pass "chattr immutable files"
fi

# ── Check 11: Docker container health ────────────────────────────────────────
log_info "Check 11/13: Docker container health"
if command -v docker &>/dev/null; then
    unhealthy=$(docker ps --filter "health=unhealthy" --format "{{.Names}}" 2>/dev/null || true)
    exited=$(docker ps -a --filter "status=exited" --filter "label=openclaw" --format "{{.Names}}" 2>/dev/null || true)

    if [[ -n "$unhealthy" ]]; then
        alert "Docker health" "Unhealthy containers: ${unhealthy}"
    elif [[ -n "$exited" ]]; then
        alert "Docker health" "Exited OpenClaw containers: ${exited}"
    else
        pass "Docker container health"
    fi
else
    log_warn "Docker not installed, skipping container health check"
    echo "[SKIP] Docker health — Docker not installed" >> "$REPORT_FILE"
fi

# ── Check 12: OpenClaw service status ────────────────────────────────────────
log_info "Check 12/13: OpenClaw service status"
if systemctl is-active --quiet openclaw 2>/dev/null; then
    # Check memory usage (RSS) of the Gateway process
    if [[ -n "${openclaw_pid:-}" ]]; then
        rss_kb=$(ps -o rss= -p "$openclaw_pid" 2>/dev/null | tr -d ' ' || echo "0")
        rss_mb=$((rss_kb / 1024))
        if [[ "$rss_mb" -gt 1800 ]]; then
            alert "OpenClaw memory" "Gateway RSS at ${rss_mb}MB (threshold: 1800MB)"
        else
            pass "OpenClaw service active (RSS: ${rss_mb}MB)"
        fi
    else
        pass "OpenClaw service active"
    fi
else
    alert "OpenClaw service" "Service is not active"
fi

# ── Check 13: Suspicious cron jobs ───────────────────────────────────────────
log_info "Check 13/13: Suspicious cron jobs"
suspicious_cron=false
suspicious_patterns="curl.*\|.*sh|wget.*\|.*sh|base64.*decode|eval |nc -|ncat |socat |/dev/tcp/"

for user_crontab in /var/spool/cron/crontabs/*; do
    if [[ -f "$user_crontab" ]]; then
        matches=$(grep -iE "$suspicious_patterns" "$user_crontab" 2>/dev/null || true)
        if [[ -n "$matches" ]]; then
            suspicious_cron=true
            user=$(basename "$user_crontab")
            alert "Suspicious cron" "User '${user}' has suspicious cron entries: ${matches}"
        fi
    fi
done

# Also check /etc/cron.d/ and /etc/crontab
for cron_file in /etc/crontab /etc/cron.d/*; do
    if [[ -f "$cron_file" ]]; then
        matches=$(grep -iE "$suspicious_patterns" "$cron_file" 2>/dev/null || true)
        if [[ -n "$matches" ]]; then
            suspicious_cron=true
            alert "Suspicious cron" "File '${cron_file}' has suspicious entries: ${matches}"
        fi
    fi
done

if [[ "$suspicious_cron" == "false" ]]; then
    pass "Suspicious cron jobs"
fi

# ── Report footer ────────────────────────────────────────────────────────────
{
    echo ""
    echo "=============================================="
    echo " Summary: ${PASS_COUNT} passed, ${ALERT_COUNT} alerts"
    echo " Report: ${REPORT_FILE}"
    echo "=============================================="
} >> "$REPORT_FILE"

echo ""
log_info "Audit complete: ${PASS_COUNT} passed, ${ALERT_COUNT} alerts"
log_info "Report saved to ${REPORT_FILE}"

# ── Send Telegram notification if requested and alerts exist ─────────────────
if [[ "$SEND_TELEGRAM" == "true" && "$ALERT_COUNT" -gt 0 ]]; then
    send_telegram_alert
fi

# Exit with non-zero if any alerts
if [[ "$ALERT_COUNT" -gt 0 ]]; then
    exit 1
fi
