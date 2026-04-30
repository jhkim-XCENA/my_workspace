#!/bin/bash
# Health-check the remote XCENA machine: power → host devices → container → container devices → sort build/run.
# Reports both host-level and container-level xcena_cli num-device for fast docker-privilege diagnosis.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/home/worker/remote/lib.sh
source "$SCRIPT_DIR/lib.sh"
load_config || exit 1

# ── 0. Power + SSH ──
log_info "[0] Power + SSH"
if ! is_device_on; then
    log_fail "Remote device is OFF — run reset.sh first"
    exit 1
fi
log_pass "Power: on"
if ! rssh "echo ssh-ok" >/dev/null 2>&1; then
    log_fail "SSH unreachable"
    exit 1
fi
log_pass "SSH: reachable"

# ── 1. Host-level xcena_cli num-device ──
log_info "[1] Host xcena_cli num-device (outside docker)"
host_out="$(rssh "xcena_cli num-device" 2>&1 || true)"
echo "$host_out" | sed 's/^/    /'
host_n="$(echo "$host_out" | grep -oP 'Number of devices : \K[0-9]+' | head -1 || true)"
if [ -z "$host_n" ] || [ "$host_n" -lt 1 ]; then
    log_fail "Host sees no devices — running PCI/driver diagnostics"
    log_info "  lspci | grep CXL:"
    rssh "lspci | grep -i CXL || echo 'no CXL device on PCI'" 2>&1 | sed 's/^/    /' || true
    log_info "  lsmod | grep mx_dma:"
    rssh "lsmod | grep mx_dma || echo 'mx_dma driver NOT loaded'" 2>&1 | sed 's/^/    /' || true
    exit 1
fi
log_pass "Host devices: $host_n"

# ── 2. Container exists + running ──
log_info "[2] Container check"
container="$(remote_latest_container)"
if [ -z "$container" ]; then
    log_fail "No jhkim_ container found on remote — run setup.sh"
    exit 1
fi
status="$(remote_container_status "$container")"
if [ "$status" != "running" ]; then
    log_fail "Container '$container' status='$status' (expected running) — try reset.sh"
    exit 1
fi
log_pass "Container: $container (running)"

# ── 3. Container-level xcena_cli num-device ──
log_info "[3] Container xcena_cli num-device (inside docker)"
cont_out="$(rdocker_exec "xcena_cli num-device" 2>&1 || true)"
echo "$cont_out" | sed 's/^/    /'
cont_n="$(echo "$cont_out" | grep -oP 'Number of devices : \K[0-9]+' | head -1 || true)"
if [ -z "$cont_n" ]; then
    log_fail "Could not parse container num-device output"
    exit 1
fi
if [ "$host_n" -ge 1 ] && [ "$cont_n" -eq 0 ]; then
    log_fail "Host=$host_n but container=0 — likely missing --privileged or /dev/mx_dma mount in docker run"
    exit 1
fi
if [ "$host_n" -ne "$cont_n" ]; then
    log_warn "device count mismatch (host=$host_n, container=$cont_n)"
else
    log_pass "Container devices: $cont_n (matches host)"
fi

# ── 4. Informational deeper device health (device 0) ──
log_info "[4] Deeper device health (device 0, informational)"

# MSUB Bitmap (single line summary)
info_out="$(rdocker_exec "xcena_cli device-info 0" 2>&1 || true)"
msub="$(echo "$info_out" | grep -i 'MSUB Bitmap' | head -1 | xargs || true)"
if [ -n "$msub" ]; then
    if echo "$msub" | grep -qE '0x0+(_0+)*\s*$|0x0$'; then
        log_warn "  $msub  (offloading unavailable)"
    else
        log_info "  $msub"
    fi
fi

# IRQ flags: count non-zero, show count + first 3 if any
err_out="$(rdocker_exec "xcena_cli debug-error 0" 2>&1 || true)"
bad="$(echo "$err_out" | awk '
    /IRQ/ && match($0, /0x[0-9a-fA-F_]+/) {
        v = substr($0, RSTART, RLENGTH)
        gsub(/^0x|_/, "", v)
        if (v ~ /[1-9a-fA-F]/) print
    }
' || true)"
if [ -n "$bad" ]; then
    bad_count="$(echo "$bad" | wc -l)"
    log_warn "  Non-zero IRQ flags: $bad_count line(s) — first 3:"
    echo "$bad" | head -3 | sed 's/^/      /'
fi

# Firmware: per-device Active Slot revision + minimum version warning.
# libpxl 3.0.0 + new mx_dma driver requires FW 1.0.7+ (see docs/remote/system_debugging.md §7);
# older FW silently fails MxDevice::initialize, so we surface this prominently.
log_info "  Firmware:"
fw_min="1.0.7"
fw_warned=0
for i in 0 1 2; do
    fw_out="$(rssh "sudo xcena_cli fw-info $i 2>&1" 2>/dev/null || true)"
    fw_rev="$(echo "$fw_out" | grep -m1 'Firmware Revision' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    if [ -z "$fw_rev" ]; then
        log_info "    device $i: (fw-info unavailable)"
        continue
    fi
    # Compare revs as dotted ints
    if [ "$(printf '%s\n%s\n' "$fw_min" "$fw_rev" | sort -V | head -1)" = "$fw_min" ]; then
        log_info "    device $i: FW $fw_rev (>= $fw_min)"
    else
        log_warn "    device $i: FW $fw_rev — below required $fw_min, libpxl 3.0.0 enumerate may fail"
        fw_warned=1
    fi
done
if [ "$fw_warned" = "1" ]; then
    log_warn "  → 유저에게 FW 업데이트 요청 후 reboot 필요"
fi

# ── 5. sort scp + build + run ──
# Use scp → remote /tmp → docker cp (instead of scp directly into a mounted path)
# so this works regardless of which directory the container has mounted as
# /home/worker (legacy containers may have /home/$REMOTE_USER bind, new
# setup.sh-produced containers have /home/$REMOTE_USER/my_workspace bind).
log_info "[5] Sort scp + build + run"
if [ ! -d "$WORKSPACE_DIR/sort" ]; then
    log_fail "$WORKSPACE_DIR/sort directory not found"
    exit 1
fi

TMP_REMOTE="/tmp/sort_check.$$"
CTR_PATH="/tmp/sort_check"
cleanup_sort() {
    rssh "rm -rf '$TMP_REMOTE'; docker exec -u root '$container' rm -rf '$CTR_PATH' 2>/dev/null || true" >/dev/null 2>&1 || true
}
trap cleanup_sort EXIT

rssh "rm -rf '$TMP_REMOTE' && mkdir -p '$TMP_REMOTE'" || { log_fail "mkdir tmp on remote failed"; exit 1; }
if ! rscp "$WORKSPACE_DIR/sort/." "$(RHOST):$TMP_REMOTE/" >/dev/null 2>&1; then
    log_fail "scp sort failed"
    exit 1
fi
log_pass "  sort copied to remote tmp"

if ! rssh "docker cp '$TMP_REMOTE/.' '$container':$CTR_PATH/ && docker exec -u root '$container' chown -R worker:worker '$CTR_PATH'" >/dev/null 2>&1; then
    log_fail "docker cp into container failed"
    exit 1
fi
log_pass "  sort placed inside container at $CTR_PATH"

# Run build.sh; success criterion is that both binaries exist afterwards.
# (sort/build.sh does not propagate ninja's exit code, so we can't rely on it.)
rdocker_exec "cd $CTR_PATH && ./build.sh" || true
if rdocker_exec "cd $CTR_PATH && [ -x build/sort_with_ndarray ] && [ -x build/sort_with_ptr ]" >/dev/null 2>&1; then
    log_pass "  sort built (both binaries present)"
    if rdocker_exec "cd $CTR_PATH && (build/sort_with_ndarray; build/sort_with_ptr)"; then
        log_pass "  sort ran"
    else
        log_warn "  sort run had non-zero exit"
    fi
else
    log_warn "  sort build artifacts missing — likely pxl API mismatch (e.g. pxl::Result vs pxl::runtime::Result). Best-effort step; not blocking."
fi

log_pass "check.sh complete"
