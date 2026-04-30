#!/bin/bash
# Run the official troubleshooting.sh on remote, pull the report locally,
# and print the validate_host.sh summary (the most useful first 40 lines).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/home/worker/remote/lib.sh
source "$SCRIPT_DIR/lib.sh"
load_config || exit 1

TS_URL="https://raw.githubusercontent.com/xcena-dev/public_sdk_release/refs/heads/main/scripts/troubleshooting.sh"
LOCAL_OUT_DIR="${TMPDIR:-/tmp}/remote_diag_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOCAL_OUT_DIR"

log_info "[1] download + run troubleshooting.sh on remote"
rssh "cd /tmp && wget -q '$TS_URL' -O ts.sh && chmod +x ts.sh && bash ts.sh > /tmp/ts.out 2>&1; echo === ts.out tail ===; tail -8 /tmp/ts.out" \
    | tee "$LOCAL_OUT_DIR/run.log"

# 보고서 파일 이름은 troubleshooting_report_<timestamp>.log 형식 — 가장 최근 것
REMOTE_REPORT="$(rssh 'ls -t /tmp/troubleshooting_report_*.log 2>/dev/null | head -1' | tr -d '\r\n')"
if [ -z "$REMOTE_REPORT" ]; then
    log_fail "원격에서 troubleshooting_report 파일을 찾지 못함"
    exit 1
fi
log_info "[2] pull report from remote: $REMOTE_REPORT"
rscp "$(RHOST):$REMOTE_REPORT" "$LOCAL_OUT_DIR/" >/dev/null

log_info "[3] validate_host.sh summary (Host Validation 섹션)"
local_report="$LOCAL_OUT_DIR/$(basename "$REMOTE_REPORT")"
sed -n '/Host Validation/,/^======/p' "$local_report" | head -50

log_info ""
log_info "[4] FAIL/WARN lines"
grep -nE '\[ ?(FAIL|WARN) ?\]|FAIL|WARN' "$local_report" | head -30 || log_pass "No FAIL/WARN lines found"

log_pass "report saved: $local_report"
