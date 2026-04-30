#!/bin/bash
# Upgrade the remote host's libpxl + mx_dma kernel driver to match a target
# container's bundled SDK version. Then reboot via BMC (calls reset.sh) so
# CXL topology re-enumerates cleanly.
#
# DESTRUCTIVE for any other docker containers on the host using device — they
# all lose access until reboot completes. Prompts for confirmation unless
# --yes is passed.
#
# Usage:
#   upgrade_host.sh              # latest jhkim_* container as source
#   upgrade_host.sh <container>  # specific container
#   upgrade_host.sh --yes        # skip confirmation
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/home/worker/remote/lib.sh
source "$SCRIPT_DIR/lib.sh"
load_config || exit 1

YES=false
SRC_CONTAINER=""
for arg in "$@"; do
    case "$arg" in
        --yes) YES=true ;;
        *)     SRC_CONTAINER="$arg" ;;
    esac
done

if [ -z "$SRC_CONTAINER" ]; then
    SRC_CONTAINER="$(remote_latest_container)"
    [ -z "$SRC_CONTAINER" ] && { log_fail "no jhkim_ container found — pass one explicitly"; exit 1; }
fi
log_info "source container: $SRC_CONTAINER"

# ── Pre-checks ──
if ! rssh "docker inspect '$SRC_CONTAINER' >/dev/null 2>&1"; then
    log_fail "container $SRC_CONTAINER not found on remote"
    exit 1
fi
DEB_PATH="$(rssh "docker exec '$SRC_CONTAINER' bash -c 'ls /work/lib/pxl/libpxl_*.deb 2>/dev/null | head -1'" | tr -d '\r\n' || true)"
if [ -z "$DEB_PATH" ]; then
    log_fail "container does not have /work/lib/pxl/libpxl_*.deb"
    exit 1
fi
log_info "found deb in container: $DEB_PATH"

# Show current vs new versions
HOST_VER="$(rssh "pxl_resourced --version 2>/dev/null | head -3 | tail -1" || echo unknown)"
NEW_VER="$(rssh "docker exec '$SRC_CONTAINER' pxl_resourced --version 2>/dev/null | head -3 | tail -1" || echo unknown)"
log_info "host pxl_resourced: $HOST_VER"
log_info "new pxl_resourced (container): $NEW_VER"

# ── Confirm ──
if [ "$YES" != true ]; then
    echo
    log_warn "This will:"
    echo "  - stop ALL running jhkim_* containers"
    echo "  - kill pxl_resourced and unload mx_dma module"
    echo "  - install new libpxl + driver from $SRC_CONTAINER"
    echo "  - reboot the remote host (~15-30 min)"
    echo
    read -r -p "Continue? (yes/no): " ans
    [ "$ans" = "yes" ] || { log_info "aborted"; exit 0; }
fi

# ── Extract assets ──
log_info "[1] docker cp libpxl deb + driver source from $SRC_CONTAINER"
rssh "docker cp '$SRC_CONTAINER':$DEB_PATH /tmp/libpxl_new.deb && \
      rm -rf /tmp/mx_dma_driver_new && \
      docker cp '$SRC_CONTAINER':/work/driver /tmp/mx_dma_driver_new" \
    || { log_fail "extract failed"; exit 1; }

# ── Stop dependents ──
log_info "[2] stop running containers + pxl_resourced"
rssh "for c in \$(docker ps -q --filter name=^jhkim_); do docker stop \$c; done; \
      sudo systemctl stop pxl_resourced 2>&1 || true; \
      sudo pkill -9 -f pxl_resourced 2>&1 || true; \
      sleep 2; \
      sudo rmmod mx_dma 2>&1 || echo 'rmmod failed (may be in use)'; \
      lsmod | grep mx_dma || echo 'mx_dma unloaded'"

# ── Install ──
log_info "[3] install new mx_dma driver (legacy/dkms)"
rssh "cd /tmp/mx_dma_driver_new && sudo bash install.sh 2>&1 | tail -20" \
    || { log_fail "driver install failed"; exit 1; }

log_info "[4] install new libpxl"
rssh "sudo dpkg -i /tmp/libpxl_new.deb 2>&1 | tail -10" \
    || { log_fail "dpkg -i failed"; exit 1; }

# ── Reboot ──
log_info "[5] reboot via BMC for clean CXL enumeration (calling reset.sh)"
log_warn "  rebooting now — SSH will drop, recovery via reset.sh will take 15-30 min"

# reset.sh handles the full off/on/check cycle
exec bash "$SCRIPT_DIR/reset.sh"
