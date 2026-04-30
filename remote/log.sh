#!/bin/bash
# Collect remote logs to a local timestamped directory:
#   - host setup.log (from latest /home/$REMOTE_USER/my_workspace/setup.log)
#   - container setup.log (inside latest jhkim_* container at /home/worker/setup.log)
#   - pxl_resourced journal (last 200 lines)
#   - sudo dmesg | grep mx_dma|cxl|xcena|err
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/home/worker/remote/lib.sh
source "$SCRIPT_DIR/lib.sh"
load_config || exit 1

OUT_DIR="${TMPDIR:-/tmp}/remote_logs_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT_DIR"
log_info "saving to $OUT_DIR"

# 1. host setup.log
log_info "[1] host setup.log"
rscp "$(RHOST):/home/$REMOTE_USER/my_workspace/setup.log" "$OUT_DIR/host_setup.log" 2>/dev/null \
    && log_pass "  saved $OUT_DIR/host_setup.log" \
    || log_warn "  host setup.log not found on remote"

# 2. container setup.log + container info
container="$(remote_latest_container)"
if [ -n "$container" ]; then
    log_info "[2] container setup.log (from $container)"
    rssh "docker cp '$container':/home/worker/setup.log /tmp/_container_setup.log 2>&1" >/dev/null 2>&1 || true
    rscp "$(RHOST):/tmp/_container_setup.log" "$OUT_DIR/container_setup.log" 2>/dev/null \
        && log_pass "  saved $OUT_DIR/container_setup.log" \
        || log_warn "  container setup.log not found"
    rssh "rm -f /tmp/_container_setup.log" >/dev/null 2>&1 || true
    rssh "docker inspect '$container' --format '{{json .Config}} {{json .HostConfig}}'" \
        > "$OUT_DIR/container_inspect.json" 2>&1 || true
else
    log_warn "[2] no jhkim_ container — skipping container logs"
fi

# 3. pxl_resourced journal
log_info "[3] pxl_resourced journal (last 200 lines)"
rssh "sudo journalctl -u pxl_resourced --no-pager -n 200" > "$OUT_DIR/pxl_resourced.journal" 2>&1 \
    && log_pass "  saved $OUT_DIR/pxl_resourced.journal" \
    || log_warn "  could not get journal"

# 4. dmesg
log_info "[4] dmesg (grep mx_dma|cxl|xcena|err|fail)"
rssh "sudo dmesg | grep -iE 'mx_dma|cxl|xcena|err|fail' | tail -200" > "$OUT_DIR/dmesg.log" 2>&1 \
    && log_pass "  saved $OUT_DIR/dmesg.log" \
    || log_warn "  could not get dmesg"

# 5. host_diag snapshot
log_info "[5] host_diag snapshot"
bash "$SCRIPT_DIR/host_diag.sh" > "$OUT_DIR/host_diag.txt" 2>&1 \
    && log_pass "  saved $OUT_DIR/host_diag.txt" \
    || log_warn "  host_diag failed"

echo
log_pass "all logs saved under: $OUT_DIR"
ls -la "$OUT_DIR"
