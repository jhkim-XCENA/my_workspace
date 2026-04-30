#!/bin/bash
# Snapshot of the remote host's XCENA stack: kernel modules, device files, PCI
# bindings, CXL regions, DAX devices, libpxl/pxl_resourced versions, xcena_cli
# version. No docker container needed — pure host-side diagnostics matching
# docs/remote/system_debugging.md §3.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/home/worker/remote/lib.sh
source "$SCRIPT_DIR/lib.sh"
load_config || exit 1

log_info "=== uptime / kernel ==="
rssh "uptime; uname -r"

log_info "=== kernel modules (mx_dma, cxl_*) ==="
rssh "lsmod | grep -E 'mx_dma|cxl_' | sort"

log_info "=== /dev/mx_dma ==="
rssh "ls /dev/mx_dma 2>&1 | head -20"

log_info "=== /dev/dax* ==="
rssh "ls -la /dev/dax* 2>&1"

log_info "=== PCI device bindings (XCENA, vendor 20a6) ==="
rssh "for bdf in \$(lspci -nn | grep -i '20a6:' | awk '{print \$1}'); do
    drv=\$(readlink /sys/bus/pci/devices/0000:\$bdf/driver 2>/dev/null | xargs -r basename || echo NOT_BOUND)
    echo \"  0000:\$bdf -> \$drv\"
done"

log_info "=== cxl list -R (regions) ==="
rssh "cxl list -R 2>&1 | head -40"

log_info "=== daxctl list ==="
rssh "daxctl list 2>&1 | head -30"

log_info "=== pxl_resourced ==="
rssh "systemctl is-active pxl_resourced 2>&1; pxl_resourced --version 2>&1 | head -3"

log_info "=== libpxl ==="
rssh "dpkg -l libpxl 2>/dev/null | tail -1"

log_info "=== xcena_cli on host ==="
rssh "which xcena_cli; xcena_cli --version 2>&1 | head -1; xcena_cli num-device 2>&1 | head -5"
