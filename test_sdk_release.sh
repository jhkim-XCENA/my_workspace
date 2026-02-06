#!/bin/bash
set -euo pipefail


# /workspaces/sdk_release를 /work/emulator/app/에 복사하여 qemu내에서 테스트하는 스크립트
# 매번 qemu 환경에서 실행하여 테스트 가능

# ──────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────
SCRIPT_DIR="/work/emulator/"
cd "${SCRIPT_DIR}"

SDK_RELEASE_SRC="/workspaces/sdk_release"
SDK_RELEASE_DST="${SCRIPT_DIR}/app/sdk_release"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOGFILE="${SCRIPT_DIR}/${TIMESTAMP}.log"
SSH_MAX_RETRIES=60
SSH_RETRY_INTERVAL=5
STEP_NUM=0

# ──────────────────────────────────────────
# Utility Functions
# ──────────────────────────────────────────
log() {
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${ts}] $*"
}

log_section() {
    log ""
    log "================================================================"
    log "  $1"
    log "================================================================"
}

log_step() {
    STEP_NUM=$((STEP_NUM + 1))
    log "--- Step ${STEP_NUM}: $1"
}

run_fatal() {
    local desc="$1"; shift
    log_step "${desc}"
    log "  HOST CMD: $*"
    if "$@"; then
        log "  OK"
    else
        local rc=$?
        log "  FAILED (exit code: ${rc})"
        log "FATAL: Aborting at step ${STEP_NUM}: ${desc}"
        exit 1
    fi
}

ssh_cmd() {
    local desc="$1"
    local cmd="$2"
    log_step "${desc}"
    log "  GUEST CMD: ${cmd}"
    if ./ssh.sh "${cmd}"; then
        log "  OK"
    else
        local rc=$?
        log "  FAILED (exit code: ${rc})"
        log "FATAL: Aborting at step ${STEP_NUM}: ${desc}"
        exit 1
    fi
}

wait_for_ssh() {
    log_step "Waiting for QEMU SSH to become available"
    local attempt=0
    while [ ${attempt} -lt ${SSH_MAX_RETRIES} ]; do
        attempt=$((attempt + 1))
        if ./ssh.sh "echo ready" >/dev/null 2>&1; then
            log "  SSH available after ${attempt} attempt(s)"
            return 0
        fi
        log "  Attempt ${attempt}/${SSH_MAX_RETRIES} - retrying in ${SSH_RETRY_INTERVAL}s..."
        sleep "${SSH_RETRY_INTERVAL}"
    done
    log "FATAL: SSH not available after ${SSH_MAX_RETRIES} attempts"
    exit 1
}

cleanup() {
    local rc=$?
    if [ ${rc} -ne 0 ]; then
        log ""
        log "================================================================"
        log "  SCRIPT FAILED at step ${STEP_NUM} (exit code: ${rc})"
        log "  Log file: ${LOGFILE}"
        log "================================================================"
    fi
}
trap cleanup EXIT

# ──────────────────────────────────────────
# Phase 1: QEMU Reset
# ──────────────────────────────────────────
phase1_qemu_reset() {
    log_section "PHASE 1: QEMU Reset"

    log_step "Kill existing QEMU (if running)"
    ./kill_bg.sh 2>&1 || true
    # kill_bg.sh only closes the screen session; QEMU process may survive.
    # Ensure all QEMU and qemu_sim processes are dead.
    pkill -f "qemu-system-x86_64.*rootfs.qcow2" 2>/dev/null || true
    pkill -f "qemu_sim" 2>/dev/null || true
    sleep 2
    # Force-kill if still alive
    pkill -9 -f "qemu-system-x86_64.*rootfs.qcow2" 2>/dev/null || true
    pkill -9 -f "qemu_sim" 2>/dev/null || true
    sleep 1
    log "  OK (kill attempted)"

    run_fatal "Restore rootfs from clean backup" \
        cp rootfs/ubuntu/rootfs.qcow2.bak rootfs/ubuntu/rootfs.qcow2

    run_fatal "Start QEMU in background" \
        ./run.sh --bg

    wait_for_ssh
}

# ──────────────────────────────────────────
# Phase 2: Sanity Check
# ──────────────────────────────────────────
phase2_sanity_check() {
    log_section "PHASE 2: Sanity Check (existing SDK)"

    ssh_cmd "Build and run existing SDK data_copy example" \
        "cd ~/sdk/example/data_copy/ && ./build.sh && ./data_copy"
}

# ──────────────────────────────────────────
# Phase 3: Copy SDK Release
# ──────────────────────────────────────────
phase3_copy_sdk_release() {
    log_section "PHASE 3: Copy SDK Release"

    log_step "Clean previous sdk_release from app/"
    rm -rf "${SDK_RELEASE_DST}"
    log "  OK"

    run_fatal "Copy SDK release to ${SDK_RELEASE_DST}" \
        cp -r "${SDK_RELEASE_SRC}" "${SDK_RELEASE_DST}"
}

# ──────────────────────────────────────────
# Phase 4: Install & Test New SDK
# ──────────────────────────────────────────
phase4_install_and_test() {
    log_section "PHASE 4: Install & Test New SDK"

    ssh_cmd "Install mu_llvm" \
        "cd ~/app/sdk_release && ./tools/mu_llvm/install.sh"

    ssh_cmd "Install mu_lib" \
        "cd ~/app/sdk_release/lib/mu_lib && ./install.sh"

    ssh_cmd "Install pxl" \
        "cd ~/app/sdk_release/lib/pxl && ./install.sh"

    ssh_cmd "Install pxcc" \
        "cd ~/app/sdk_release/tools/pxcc && ./install.sh"

    ssh_cmd "Build and run data_copy integration test" \
        "cd ~/app/sdk_release/tools/pxcc/integrated_tests/examples/data_copy && ./build.sh && ./data_copy"
}

# ──────────────────────────────────────────
# Main
# ──────────────────────────────────────────
main() {
    exec > >(tee -a "${LOGFILE}") 2>&1

    log "============================================"
    log "  CXL Emulator SDK Release Test"
    log "  Log: ${LOGFILE}"
    log "============================================"

    phase1_qemu_reset
    phase2_sanity_check
    phase3_copy_sdk_release
    phase4_install_and_test

    log_section "ALL PHASES COMPLETED SUCCESSFULLY"
    log "Full log: ${LOGFILE}"
}

main "$@"
