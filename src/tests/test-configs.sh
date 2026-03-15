#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# test-configs.sh — Configuration file validation tests
#
# Validates JSON5, YAML, and INI config files for syntax errors
# and scans for hardcoded secrets.
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIGS_DIR="${REPO_ROOT}/src/configs"

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

# ── JSON5 validation ────────────────────────────────────────────────────────
validate_json5() {
    log_info "Validating JSON5 files..."

    local found=false
    while IFS= read -r -d '' file; do
        found=true
        local basename
        basename=$(basename "$file")

        # JSON5 supports comments and trailing commas.
        # Strip single-line comments (//) and try parsing as JSON.
        # This is a lightweight check — for full JSON5 validation use a dedicated parser.
        local stripped
        stripped=$(sed 's|//.*$||' "$file" | sed 's|,\s*}|}|g' | sed 's|,\s*]|]|g')

        if echo "$stripped" | python3 -m json.tool > /dev/null 2>&1; then
            pass "JSON5 syntax OK: ${basename}"
        else
            # Try node if available (native JSON5 support)
            if command -v node &>/dev/null; then
                if node -e "
                    const fs = require('fs');
                    try { JSON.parse(fs.readFileSync('${file}', 'utf8').replace(/\/\/.*/g,'').replace(/,(\s*[}\]])/g,'\$1')); process.exit(0); }
                    catch(e) { process.exit(1); }
                " 2>/dev/null; then
                    pass "JSON5 syntax OK: ${basename} (via node)"
                else
                    fail "JSON5 syntax ERROR: ${basename}"
                fi
            else
                fail "JSON5 syntax ERROR: ${basename} (install python3 or node for validation)"
            fi
        fi
    done < <(find "$CONFIGS_DIR" -name "*.json5" -print0 2>/dev/null)

    if [[ "$found" == "false" ]]; then
        log_warn "No JSON5 files found in ${CONFIGS_DIR}"
    fi
}

# ── YAML validation ─────────────────────────────────────────────────────────
validate_yaml() {
    log_info "Validating YAML files..."

    local found=false
    while IFS= read -r -d '' file; do
        found=true
        local basename
        basename=$(basename "$file")

        if command -v python3 &>/dev/null; then
            if python3 -c "
import yaml, sys
try:
    with open('${file}') as f:
        yaml.safe_load(f)
    sys.exit(0)
except Exception as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
" 2>/dev/null; then
                pass "YAML syntax OK: ${basename}"
            else
                fail "YAML syntax ERROR: ${basename}"
            fi
        elif command -v ruby &>/dev/null; then
            if ruby -ryaml -e "YAML.safe_load(File.read('${file}'))" 2>/dev/null; then
                pass "YAML syntax OK: ${basename}"
            else
                fail "YAML syntax ERROR: ${basename}"
            fi
        else
            # Minimal check: ensure no tab indentation (YAML disallows tabs)
            if grep -Pn '^\t' "$file" > /dev/null 2>&1; then
                fail "YAML contains tabs: ${basename} (YAML requires spaces for indentation)"
            else
                pass "YAML basic check OK: ${basename} (install python3 for full validation)"
            fi
        fi
    done < <(find "$CONFIGS_DIR" -name "*.yaml" -o -name "*.yml" -print0 2>/dev/null)

    if [[ "$found" == "false" ]]; then
        log_warn "No YAML files found in ${CONFIGS_DIR}"
    fi
}

# ── INI validation ───────────────────────────────────────────────────────────
validate_ini() {
    log_info "Validating INI files..."

    local found=false
    while IFS= read -r -d '' file; do
        found=true
        local basename
        basename=$(basename "$file")

        # Basic INI validation: every non-empty, non-comment line must be a section header or key=value
        local errors=0
        local line_num=0
        while IFS= read -r line; do
            line_num=$((line_num + 1))
            # Skip empty lines and comments
            [[ -z "$line" || "$line" =~ ^[[:space:]]*[#\;] ]] && continue
            # Section header: [something]
            [[ "$line" =~ ^[[:space:]]*\[.*\][[:space:]]*$ ]] && continue
            # Key = value (with optional spaces)
            [[ "$line" =~ ^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_.-]*[[:space:]]*= ]] && continue
            # If none matched, it's an error
            errors=$((errors + 1))
            log_warn "  Line ${line_num}: unexpected content: ${line}"
        done < "$file"

        if [[ "$errors" -eq 0 ]]; then
            pass "INI syntax OK: ${basename}"
        else
            fail "INI syntax ERROR: ${basename} (${errors} issues)"
        fi
    done < <(find "$CONFIGS_DIR" -name "*.local" -o -name "*.ini" -o -name "*.conf" -print0 2>/dev/null)

    if [[ "$found" == "false" ]]; then
        log_warn "No INI files found in ${CONFIGS_DIR}"
    fi
}

# ── Hardcoded secrets scan ───────────────────────────────────────────────────
scan_secrets() {
    log_info "Scanning for hardcoded secrets..."

    local secrets_found=false

    # Patterns that indicate real secrets (not placeholders)
    local patterns=(
        'sk-[a-zA-Z0-9]{20,}'                    # OpenAI API keys
        'sk-ant-[a-zA-Z0-9]{20,}'                # Anthropic API keys
        'ghp_[a-zA-Z0-9]{36}'                    # GitHub PATs
        'gho_[a-zA-Z0-9]{36}'                    # GitHub OAuth tokens
        'xoxb-[0-9]+-[0-9]+-[a-zA-Z0-9]+'        # Slack bot tokens
        'xoxp-[0-9]+-[0-9]+-[a-zA-Z0-9]+'        # Slack user tokens
        '[0-9]+:AA[a-zA-Z0-9_-]{33}'              # Telegram bot tokens
        'password\s*[:=]\s*["\x27][^"\x27]{8,}'   # Hardcoded passwords
        'secret\s*[:=]\s*["\x27][^"\x27]{8,}'     # Hardcoded secrets
    )

    while IFS= read -r -d '' file; do
        local basename
        basename=$(basename "$file")

        for pattern in "${patterns[@]}"; do
            local matches
            matches=$(grep -nE "$pattern" "$file" 2>/dev/null || true)
            if [[ -n "$matches" ]]; then
                # Filter out known placeholder patterns
                local real_matches
                real_matches=$(echo "$matches" | grep -v 'REPLACE_WITH\|GENERATE_WITH\|\${' || true)
                if [[ -n "$real_matches" ]]; then
                    secrets_found=true
                    fail "Potential secret in ${basename}: $(echo "$real_matches" | head -1)"
                fi
            fi
        done
    done < <(find "$CONFIGS_DIR" -type f -print0 2>/dev/null)

    if [[ "$secrets_found" == "false" ]]; then
        pass "No hardcoded secrets detected"
    fi
}

# ── systemd unit validation ──────────────────────────────────────────────────
validate_systemd() {
    log_info "Validating systemd unit files..."

    local found=false
    while IFS= read -r -d '' file; do
        found=true
        local basename
        basename=$(basename "$file")

        # Check for required sections
        local has_unit=false has_service=false has_install=false

        grep -q '^\[Unit\]' "$file" 2>/dev/null && has_unit=true
        grep -q '^\[Service\]' "$file" 2>/dev/null && has_service=true
        grep -q '^\[Install\]' "$file" 2>/dev/null && has_install=true

        if [[ "$has_service" == "true" ]]; then
            if [[ "$basename" == *.service && "$has_unit" == "true" && "$has_install" == "true" ]]; then
                pass "systemd unit OK: ${basename}"
            elif [[ "$basename" == *.conf ]]; then
                pass "systemd override OK: ${basename}"
            else
                fail "systemd unit missing sections: ${basename} (Unit=${has_unit}, Service=${has_service}, Install=${has_install})"
            fi
        elif [[ "$basename" == *.conf && "$has_service" == "false" ]]; then
            # For .conf overrides, [Service] is expected
            local has_any_section=false
            grep -q '^\[' "$file" 2>/dev/null && has_any_section=true
            if [[ "$has_any_section" == "true" ]]; then
                pass "systemd override OK: ${basename}"
            else
                fail "systemd file has no sections: ${basename}"
            fi
        fi
    done < <(find "$CONFIGS_DIR/systemd" -type f \( -name "*.service" -o -name "*.conf" \) -print0 2>/dev/null)

    if [[ "$found" == "false" ]]; then
        log_warn "No systemd unit files found"
    fi
}

# ── Run all checks ──────────────────────────────────────────────────────────
echo ""
log_info "OpenClaw Config Validation"
echo "─────────────────────────────────────────────"
echo ""

validate_json5
echo ""
validate_yaml
echo ""
validate_ini
echo ""
validate_systemd
echo ""
scan_secrets

echo ""
echo "─────────────────────────────────────────────"
if [[ "$FAIL_COUNT" -gt 0 ]]; then
    log_error "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
    exit 1
else
    log_success "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
    exit 0
fi
