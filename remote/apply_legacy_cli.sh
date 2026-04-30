#!/bin/bash
# Hot-patch the legacy xcena_cli into a running container (replacing the
# broken SDK 1.4.5 binary). Used for fixing already-running containers — new
# containers get the same patch automatically via launch_docker_container.sh.
#
# Usage:
#   apply_legacy_cli.sh                # latest jhkim_* container
#   apply_legacy_cli.sh <container>    # specific container
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/home/worker/remote/lib.sh
source "$SCRIPT_DIR/lib.sh"
load_config || exit 1

LEGACY_CLI="$WORKSPACE_DIR/binaries/xcena_cli.legacy"
if [ ! -f "$LEGACY_CLI" ]; then
    log_fail "$LEGACY_CLI not found"
    exit 1
fi

CONTAINER="${1:-}"
if [ -z "$CONTAINER" ]; then
    CONTAINER="$(remote_latest_container)"
    [ -z "$CONTAINER" ] && { log_fail "no jhkim_ container found"; exit 1; }
    log_info "using latest container: $CONTAINER"
fi

REMOTE_TMP="/tmp/xcena_cli.legacy.$$"
log_info "[1] scp legacy binary → $(RHOST):$REMOTE_TMP"
rscp "$LEGACY_CLI" "$(RHOST):$REMOTE_TMP" >/dev/null \
    || { log_fail "scp failed"; exit 1; }

log_info "[2] docker cp → ${CONTAINER}:/usr/local/bin/xcena_cli"
rssh "docker cp '$REMOTE_TMP' '$CONTAINER':/usr/local/bin/xcena_cli && \
      docker exec -u root '$CONTAINER' chmod +x /usr/local/bin/xcena_cli && \
      rm -f '$REMOTE_TMP'" \
    || { log_fail "docker cp/chmod failed"; exit 1; }

log_info "[3] verify"
out="$(rssh "docker exec -u worker '$CONTAINER' xcena_cli num-device" 2>&1)"
echo "$out" | sed 's/^/    /'
n="$(echo "$out" | grep -oP 'Number of devices : \K[0-9]+' | head -1 || true)"
if [ -n "$n" ] && [ "$n" -ge 1 ]; then
    log_pass "legacy xcena_cli detects $n device(s)"
else
    log_warn "legacy xcena_cli reports 0 — host stack may also be unhealthy. Try: bash $SCRIPT_DIR/host_diag.sh"
fi
