#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# test-security.sh — Security validation tests for OpenClaw scripts
#
# Runs shellcheck on all .sh files, verifies executable permissions,
# and checks for common security anti-patterns.
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../scripts/common.sh
source "${SCRIPT_DIR}/../scripts/common.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    log_success "$*"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    log_error "$*"
}

# ── Collect all .sh files ────────────────────────────────────────────────────
mapfile -t SH_FILES < <(find "$REPO_ROOT" -name "*.sh" -type f -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | sort)

if [[ ${#SH_FILES[@]} -eq 0 ]]; then
    log_warn "No .sh files found in ${REPO_ROOT}"
    exit 0
fi

log_info "Found ${#SH_FILES[@]} shell scripts to validate"
echo ""

# ── Test 1: shellcheck ───────────────────────────────────────────────────────
run_shellcheck() {
    log_info "Running shellcheck on all .sh files..."

    if ! command -v shellcheck &>/dev/null; then
        log_warn "shellcheck not installed — install with: brew install shellcheck (macOS) or apt install shellcheck (Debian/Ubuntu)"
        fail "shellcheck not available"
        return
    fi

    local shellcheck_fails=0

    for file in "${SH_FILES[@]}"; do
        local relpath="${file#"${REPO_ROOT}/"}"

        if shellcheck -x -S warning "$file" 2>/dev/null; then
            pass "shellcheck OK: ${relpath}"
        else
            shellcheck_fails=$((shellcheck_fails + 1))
            fail "shellcheck FAIL: ${relpath}"
            # Show first few issues
            shellcheck -x -S warning -f gcc "$file" 2>/dev/null | head -5 || true
        fi
    done

    if [[ "$shellcheck_fails" -eq 0 ]]; then
        log_success "All scripts passed shellcheck"
    fi
}

# ── Test 2: Executable permissions ───────────────────────────────────────────
check_executable() {
    log_info "Verifying executable permissions on .sh files..."

    for file in "${SH_FILES[@]}"; do
        local relpath="${file#"${REPO_ROOT}/"}"

        if [[ -x "$file" ]]; then
            pass "Executable: ${relpath}"
        else
            fail "Not executable: ${relpath} — fix with: chmod +x ${relpath}"
        fi
    done
}

# ── Test 3: Shebang line ────────────────────────────────────────────────────
check_shebang() {
    log_info "Verifying shebang lines..."

    for file in "${SH_FILES[@]}"; do
        local relpath="${file#"${REPO_ROOT}/"}"
        local first_line
        first_line=$(head -1 "$file")

        if [[ "$first_line" == "#!/usr/bin/env bash" || "$first_line" == "#!/bin/bash" ]]; then
            pass "Shebang OK: ${relpath}"
        else
            fail "Missing or wrong shebang: ${relpath} (got: '${first_line}')"
        fi
    done
}

# ── Test 4: set -euo pipefail ───────────────────────────────────────────────
check_strict_mode() {
    log_info "Verifying strict mode (set -euo pipefail)..."

    for file in "${SH_FILES[@]}"; do
        local relpath="${file#"${REPO_ROOT}/"}"

        if grep -q 'set -euo pipefail' "$file" 2>/dev/null; then
            pass "Strict mode: ${relpath}"
        else
            fail "Missing 'set -euo pipefail': ${relpath}"
        fi
    done
}

# ── Test 5: Security anti-patterns ──────────────────────────────────────────
check_antipatterns() {
    log_info "Checking for security anti-patterns..."

    local antipatterns_found=false

    for file in "${SH_FILES[@]}"; do
        local relpath="${file#"${REPO_ROOT}/"}"

        # Check for eval usage (potential code injection)
        local eval_matches
        eval_matches=$(grep -n '\beval\b' "$file" 2>/dev/null | grep -v '^\s*#' || true)
        if [[ -n "$eval_matches" ]]; then
            antipatterns_found=true
            fail "eval usage in ${relpath}: $(echo "$eval_matches" | head -1)"
        fi

        # Check for curl|bash or wget|bash without verification
        local pipe_exec
        pipe_exec=$(grep -nE 'curl\s.*\|\s*(sudo\s+)?bash|wget\s.*\|\s*(sudo\s+)?bash|curl\s.*\|\s*(sudo\s+)?sh|wget\s.*\|\s*(sudo\s+)?sh' "$file" 2>/dev/null | grep -v '^\s*#' || true)
        if [[ -n "$pipe_exec" ]]; then
            antipatterns_found=true
            fail "curl|bash pattern in ${relpath}: $(echo "$pipe_exec" | head -1)"
        fi

        # Check for chmod 777
        local chmod_777
        chmod_777=$(grep -n 'chmod.*777' "$file" 2>/dev/null | grep -v '^\s*#' || true)
        if [[ -n "$chmod_777" ]]; then
            antipatterns_found=true
            fail "chmod 777 in ${relpath}: $(echo "$chmod_777" | head -1)"
        fi

        # Check for hardcoded /tmp usage without mktemp
        local tmp_usage
        tmp_usage=$(grep -n '"/tmp/' "$file" 2>/dev/null | grep -v '^\s*#\|mktemp\|PrivateTmp' || true)
        if [[ -n "$tmp_usage" ]]; then
            antipatterns_found=true
            fail "Hardcoded /tmp path in ${relpath}: $(echo "$tmp_usage" | head -1) — use mktemp instead"
        fi

        # Check for unquoted variables in dangerous positions
        local unquoted
        unquoted=$(grep -nE '\$\{?[A-Za-z_][A-Za-z0-9_]*\}?\s' "$file" 2>/dev/null | grep -E '^\s*(rm|mv|cp|cat|chmod|chown)\s' | grep -v '^\s*#' || true)
        if [[ -n "$unquoted" ]]; then
            # This is a heuristic — may have false positives
            log_warn "Potentially unquoted variable in ${relpath}: $(echo "$unquoted" | head -1)"
        fi
    done

    if [[ "$antipatterns_found" == "false" ]]; then
        pass "No security anti-patterns detected"
    fi
}

# ── Test 6: Safety functions exist in common.sh ───────────────────────────
test_safety_functions() {
    local common_sh="$REPO_ROOT/src/scripts/common.sh"
    local functions=(backup_config restore_config verify_ssh_access verify_ufw_rule verify_service safe_chattr setup_trap_handler)
    local missing=0

    for func in "${functions[@]}"; do
        if ! grep -q "^${func}()" "$common_sh" 2>/dev/null; then
            fail "Safety function '${func}' not found in common.sh"
            ((missing++))
        fi
    done

    if [[ $missing -eq 0 ]]; then
        pass "All 7 safety functions present in common.sh"
        return 0
    else
        fail "$missing safety function(s) missing from common.sh"
        return 1
    fi
}

# ── Test 7: 02-harden-server.sh uses safety functions ────────────────────
test_harden_uses_safety() {
    local harden_sh="$REPO_ROOT/src/scripts/02-harden-server.sh"
    local has_pass=true

    grep -q "verify_ufw_rule" "$harden_sh" || { fail "02-harden-server.sh missing verify_ufw_rule call"; has_pass=false; }
    grep -q "verify_ssh_access" "$harden_sh" || { fail "02-harden-server.sh missing verify_ssh_access call"; has_pass=false; }
    grep -q "safe_chattr" "$harden_sh" || { fail "02-harden-server.sh missing safe_chattr call"; has_pass=false; }

    if $has_pass; then
        pass "02-harden-server.sh uses all required safety functions"
        return 0
    fi
    return 1
}

# ── Test 8: No bare chattr +i outside safe_chattr definition ─────────────
test_no_bare_chattr() {
    local has_pass=true

    for script in "$REPO_ROOT"/src/scripts/[0-9]*.sh; do
        local bare_count
        bare_count=$(grep -c "chattr +i" "$script" 2>/dev/null) || bare_count=0
        local safe_count
        safe_count=$(grep -c "safe_chattr" "$script" 2>/dev/null) || safe_count=0

        if [[ $bare_count -gt 0 && $safe_count -eq 0 ]]; then
            fail "$(basename "$script") has bare 'chattr +i' without safe_chattr"
            has_pass=false
        fi
    done

    if $has_pass; then
        pass "No bare chattr +i found outside safe_chattr usage"
        return 0
    fi
    return 1
}

# ── Run all checks ──────────────────────────────────────────────────────────
echo ""
log_info "OpenClaw Security Validation"
echo "─────────────────────────────────────────────"
echo ""

run_shellcheck
echo ""
check_executable
echo ""
check_shebang
echo ""
check_strict_mode
echo ""
check_antipatterns
echo ""
test_safety_functions
echo ""
test_harden_uses_safety
echo ""
test_no_bare_chattr

echo ""
echo "─────────────────────────────────────────────"
if [[ "$FAIL_COUNT" -gt 0 ]]; then
    log_error "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
    exit 1
else
    log_success "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
    exit 0
fi
