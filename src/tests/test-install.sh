#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# test-install.sh — Docker-based install test for OpenClaw
#
# Builds an Ubuntu 22.04 container, copies the repo into it,
# and validates that scripts source correctly and pass basic checks.
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../scripts/common.sh
source "${SCRIPT_DIR}/../scripts/common.sh"

CONTAINER_NAME="openclaw-install-test-$$"
TEST_IMAGE="openclaw-test:latest"
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

# ── Prerequisite check ──────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    log_error "Docker is required but not installed."
    log_info "Install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! docker info &>/dev/null; then
    log_error "Docker daemon is not running."
    exit 1
fi

# ── Cleanup function ────────────────────────────────────────────────────────
cleanup() {
    log_info "Cleaning up..."
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    docker rmi -f "$TEST_IMAGE" 2>/dev/null || true
}
trap cleanup EXIT

# ── Build test image ────────────────────────────────────────────────────────
log_info "Building test container from Ubuntu 22.04..."

DOCKERFILE=$(cat <<'DOCKERFILE_CONTENT'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    coreutils \
    findutils \
    grep \
    sed \
    gawk \
    python3 \
    python3-yaml \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/openclaw-repo
WORKDIR /opt/openclaw-repo
DOCKERFILE_CONTENT
)

echo "$DOCKERFILE" | docker build -t "$TEST_IMAGE" -f - "$REPO_ROOT"
log_success "Test image built"

# ── Start container ──────────────────────────────────────────────────────────
log_info "Starting test container..."
docker run -d --name "$CONTAINER_NAME" \
    -v "${REPO_ROOT}:/opt/openclaw-repo:ro" \
    "$TEST_IMAGE" \
    sleep 300

log_success "Container started: ${CONTAINER_NAME}"

# ── Helper: run command in container ─────────────────────────────────────────
run_in_container() {
    docker exec "$CONTAINER_NAME" bash -c "$*"
}

echo ""
log_info "OpenClaw Install Validation"
echo "─────────────────────────────────────────────"
echo ""

# ── Test 1: Verify repo structure ────────────────────────────────────────────
log_info "Test 1: Verify repo structure..."

if run_in_container "test -d /opt/openclaw-repo/src/configs"; then
    pass "src/configs/ exists"
else
    fail "src/configs/ missing"
fi

if run_in_container "test -d /opt/openclaw-repo/src/security"; then
    pass "src/security/ exists"
else
    fail "src/security/ missing"
fi

if run_in_container "test -d /opt/openclaw-repo/src/tests"; then
    pass "src/tests/ exists"
else
    fail "src/tests/ missing"
fi

if run_in_container "test -d /opt/openclaw-repo/src/scripts"; then
    pass "src/scripts/ exists"
else
    fail "src/scripts/ missing"
fi

# ── Test 2: Verify common.sh sources correctly ──────────────────────────────
log_info "Test 2: Verify common.sh sources correctly..."

if run_in_container "source /opt/openclaw-repo/src/scripts/common.sh && type log_info &>/dev/null"; then
    pass "common.sh sources and defines log_info"
else
    fail "common.sh failed to source"
fi

if run_in_container "source /opt/openclaw-repo/src/scripts/common.sh && type log_error &>/dev/null"; then
    pass "common.sh defines log_error"
else
    fail "common.sh missing log_error"
fi

if run_in_container "source /opt/openclaw-repo/src/scripts/common.sh && type step &>/dev/null"; then
    pass "common.sh defines step"
else
    fail "common.sh missing step"
fi

# ── Test 3: Verify config files exist and have content ───────────────────────
log_info "Test 3: Verify config files..."

config_files=(
    "src/configs/openclaw.json5"
    "src/configs/gateway.yaml"
    "src/configs/fail2ban-jail.local"
    "src/configs/systemd/openclaw.service"
    "src/configs/systemd/openclaw-resources.conf"
)

for cf in "${config_files[@]}"; do
    if run_in_container "test -s /opt/openclaw-repo/${cf}"; then
        pass "Config exists and non-empty: ${cf}"
    else
        fail "Config missing or empty: ${cf}"
    fi
done

# ── Test 4: Verify security scripts exist and have shebangs ─────────────────
log_info "Test 4: Verify security scripts..."

security_scripts=(
    "src/security/nightly-audit.sh"
    "src/security/agent-brain-backup.sh"
)

for ss in "${security_scripts[@]}"; do
    if run_in_container "test -s /opt/openclaw-repo/${ss}"; then
        pass "Script exists and non-empty: ${ss}"
    else
        fail "Script missing or empty: ${ss}"
    fi

    shebang=$(run_in_container "head -1 /opt/openclaw-repo/${ss}" || true)
    if [[ "$shebang" == "#!/usr/bin/env bash" ]]; then
        pass "Correct shebang: ${ss}"
    else
        fail "Wrong shebang in ${ss}: '${shebang}'"
    fi
done

# ── Test 5: Verify egress whitelist ──────────────────────────────────────────
log_info "Test 5: Verify egress whitelist..."

if run_in_container "test -s /opt/openclaw-repo/src/security/egress-whitelist.txt"; then
    pass "Egress whitelist exists"
else
    fail "Egress whitelist missing"
fi

# Check that required domains are in the whitelist
required_domains=("api.openai.com" "api.anthropic.com" "api.telegram.org")
for domain in "${required_domains[@]}"; do
    if run_in_container "grep -q '${domain}' /opt/openclaw-repo/src/security/egress-whitelist.txt"; then
        pass "Whitelist contains: ${domain}"
    else
        fail "Whitelist missing: ${domain}"
    fi
done

# ── Test 6: Verify YAML config is valid ──────────────────────────────────────
log_info "Test 6: YAML validation inside container..."

if run_in_container "python3 -c \"
import yaml, sys
try:
    with open('/opt/openclaw-repo/src/configs/gateway.yaml') as f:
        yaml.safe_load(f)
    sys.exit(0)
except Exception as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
\""; then
    pass "gateway.yaml is valid YAML"
else
    fail "gateway.yaml is not valid YAML"
fi

# ── Test 7: Verify JSON5 config has required keys ────────────────────────────
log_info "Test 7: JSON5 config key validation..."

required_keys=("gateway" "agents" "session" "logging" "browser" "plugins" "channels")
for key in "${required_keys[@]}"; do
    if run_in_container "grep -q '\"${key}\"' /opt/openclaw-repo/src/configs/openclaw.json5"; then
        pass "openclaw.json5 contains key: ${key}"
    else
        fail "openclaw.json5 missing key: ${key}"
    fi
done

# ── Test 8: Verify systemd service has required sections ─────────────────────
log_info "Test 8: systemd service structure..."

for section in "\\[Unit\\]" "\\[Service\\]" "\\[Install\\]"; do
    if run_in_container "grep -q '${section}' /opt/openclaw-repo/src/configs/systemd/openclaw.service"; then
        pass "openclaw.service has section: ${section}"
    else
        fail "openclaw.service missing section: ${section}"
    fi
done

# ── Test 9: Verify no hardcoded secrets ──────────────────────────────────────
log_info "Test 9: No hardcoded secrets..."

secret_patterns="sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|xoxb-[0-9]+"
if run_in_container "grep -rE '${secret_patterns}' /opt/openclaw-repo/src/configs/ 2>/dev/null | grep -v 'REPLACE_WITH\|GENERATE_WITH\|\\\${'"; then
    fail "Hardcoded secrets found in config files"
else
    pass "No hardcoded secrets in configs"
fi

# ── Results ──────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────────"
if [[ "$FAIL_COUNT" -gt 0 ]]; then
    log_error "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
    exit 1
else
    log_success "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
    exit 0
fi
