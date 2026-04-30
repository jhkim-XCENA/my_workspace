#!/bin/bash
# Power-cycle the remote XCENA machine and recover the docker container:
#   1. power off (5 retries × 5 min wait)
#   2. power on (10 min wait)
#   3. wait for SSH (up to 15 min — OS boot + sshd)
#   4. recovery branch:
#        - check.sh passes → done
#        - container exists but stopped → docker start, retry check.sh
#        - no container → exec setup.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/home/worker/remote/lib.sh
source "$SCRIPT_DIR/lib.sh"
load_config || exit 1

# ── 1. Off cycle ──
log_info "[1] Powering off (up to 5 attempts × 5min wait)"
off_done=false
for attempt in 1 2 3 4 5; do
    log_info "  off attempt $attempt"
    power_off >/dev/null || true
    if wait_for_state off 300 15; then
        log_pass "Powered off"
        off_done=true
        break
    fi
    log_warn "  attempt $attempt timed out — still on"
done
if [ "$off_done" = false ]; then
    log_fail "Failed to power off after 5 attempts"
    exit 1
fi

# ── 2. On ──
log_info "[2] Powering on (up to 10 min)"
power_on >/dev/null || true
if ! wait_for_state on 600 15; then
    log_fail "Failed to power on within 10 min"
    exit 1
fi
log_pass "Powered on"

# ── 3. SSH ready ──
log_info "[3] Waiting for SSH (up to 15 min — OS boot delay)"
if ! wait_for_ssh 900 10; then
    log_fail "SSH did not become reachable within 15 min"
    exit 1
fi
log_pass "SSH: reachable"

# ── 4. Recovery branch ──
log_info "[4] Verifying with check.sh"
if bash "$SCRIPT_DIR/check.sh"; then
    log_pass "reset.sh complete (no recovery needed)"
    exit 0
fi

log_warn "check.sh failed — attempting recovery"
container="$(remote_latest_container)"
if [ -n "$container" ]; then
    status="$(remote_container_status "$container")"
    log_info "Found container '$container' (status='$status') — issuing docker start"
    rssh "docker start '$container'" >/dev/null 2>&1 || true
    sleep 5
    if bash "$SCRIPT_DIR/check.sh"; then
        log_pass "Recovered via docker start"
        exit 0
    fi
    log_warn "docker start did not recover — falling through to setup.sh"
fi

log_warn "No usable container — running setup.sh"
exec bash "$SCRIPT_DIR/setup.sh"
