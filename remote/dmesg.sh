#!/bin/bash
# Remote sudo dmesg with sensible default grep.
# Usage:
#   dmesg.sh                       # mx_dma/cxl/xcena/err/fail 패턴
#   dmesg.sh 'pattern'             # 임의 grep 패턴
#   dmesg.sh --all                 # grep 없이 전체 dmesg tail
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/home/worker/remote/lib.sh
source "$SCRIPT_DIR/lib.sh"
load_config || exit 1

if [ "${1:-}" = "--all" ]; then
    rssh "sudo dmesg | tail -100"
else
    PATTERN="${1:-mx_dma|cxl|xcena|err|fail|warn}"
    rssh "sudo dmesg | grep -iE '$PATTERN' | tail -80"
fi
