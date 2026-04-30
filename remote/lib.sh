#!/bin/bash
# Common helpers for remote/ scripts.
# Source from a script via: source "$(dirname "$0")/lib.sh"

REMOTE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "$REMOTE_LIB_DIR/.." && pwd)"

# ── Logging ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; GRAY='\033[0;90m'; NC='\033[0m'
log_info() { echo -e "${GRAY}[$(date +%H:%M:%S)]${NC} $*"; }
log_pass() { echo -e "${GREEN}[ok]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
log_fail() { echo -e "${RED}[fail]${NC} $*" >&2; }

# ── Config ──
load_config() {
    if [ ! -f "$WORKSPACE_DIR/config.sh" ]; then
        log_fail "config.sh not found at $WORKSPACE_DIR/config.sh"
        return 1
    fi
    # shellcheck disable=SC1091
    source "$WORKSPACE_DIR/config.sh"
    if [ -z "${REMOTE_IP:-}" ];       then log_fail "REMOTE_IP empty in config.sh";       return 1; fi
    if [ -z "${REMOTE_USER:-}" ];     then log_fail "REMOTE_USER empty in config.sh";     return 1; fi
    if [ -z "${REMOTE_PASSWORD:-}" ]; then log_fail "REMOTE_PASSWORD empty in config.sh"; return 1; fi
}

# ── Power API (BMC proxy) ──
POWER_API_BASE="http://192.168.57.60:8002/api/power"
power_status() { curl -fsS -X POST "$POWER_API_BASE/$REMOTE_IP/status"; }
power_on()     { curl -fsS -X POST "$POWER_API_BASE/$REMOTE_IP/on"; }
power_off()    { curl -fsS -X POST "$POWER_API_BASE/$REMOTE_IP/off"; }

is_device_on() {
    local resp
    resp="$(power_status 2>/dev/null)" || return 1
    echo "$resp" | grep -q '"device_on":true'
}

# wait_for_state <on|off> [timeout=300] [interval=10]
wait_for_state() {
    local desired="$1" timeout="${2:-300}" interval="${3:-10}"
    local start=$SECONDS
    while [ $((SECONDS - start)) -lt "$timeout" ]; do
        if is_device_on; then
            [ "$desired" = "on" ] && return 0
        else
            [ "$desired" = "off" ] && return 0
        fi
        sleep "$interval"
    done
    return 1
}

# ── SSH/SCP wrappers ──
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o LogLevel=ERROR -o UserKnownHostsFile="$HOME/.ssh/known_hosts")

rssh() {
    sshpass -p "$REMOTE_PASSWORD" ssh "${SSH_OPTS[@]}" "${REMOTE_USER}@${REMOTE_IP}" "$@"
}

rssh_tty() {
    # -tt forces pty allocation even when local stdin is not a tty (so docker exec -it works
    # whether ssh_docker.sh is invoked interactively or from a script).
    sshpass -p "$REMOTE_PASSWORD" ssh -tt "${SSH_OPTS[@]}" "${REMOTE_USER}@${REMOTE_IP}" "$@"
}

rscp() {
    sshpass -p "$REMOTE_PASSWORD" scp -r "${SSH_OPTS[@]}" "$@"
}

RHOST() { echo "${REMOTE_USER}@${REMOTE_IP}"; }

# wait_for_ssh [timeout=900] [interval=10]
# Power-on of the remote does NOT guarantee SSH readiness — the OS still has to
# boot and sshd must come up. This can take 5–15 min in practice.
wait_for_ssh() {
    local timeout="${1:-900}" interval="${2:-10}"
    local start=$SECONDS
    while [ $((SECONDS - start)) -lt "$timeout" ]; do
        if rssh "echo ssh-ok" >/dev/null 2>&1; then
            return 0
        fi
        sleep "$interval"
    done
    return 1
}

# ── Container discovery (on remote) ──
remote_latest_container() {
    rssh 'docker ps -a --filter "name=^jhkim_" --format "{{.CreatedAt}}\t{{.Names}}" | sort -r | head -1 | cut -f2-' \
        | tr -d '\r\n'
}

remote_container_status() {
    local name="$1"
    rssh "docker inspect -f '{{.State.Status}}' '$name' 2>/dev/null" | tr -d '\r\n'
}

# Run command inside latest container on remote (worker user, /home/worker cwd).
# Uses non-tty SSH (suitable for capturing stdout in $(...)).
#
# Note: avoid `docker exec -w /home/worker` — when the container is launched
# with --userns=host (silicon mode), -w trips Docker's mount-namespace check
# ("current working directory is outside of container mount namespace root").
# We `cd` inside the bash invocation instead.
rdocker_exec() {
    local container
    container="$(remote_latest_container)"
    if [ -z "$container" ]; then
        log_fail "no jhkim_ container found on remote"
        return 1
    fi
    local cmd
    cmd="$(printf '%q' "cd /home/worker 2>/dev/null; $*")"
    rssh "docker exec -u worker '$container' bash -lc $cmd"
}

# Same as rdocker_exec, with TTY allocation (interactive).
rdocker_exec_tty() {
    local container
    container="$(remote_latest_container)"
    if [ -z "$container" ]; then
        log_fail "no jhkim_ container found on remote"
        return 1
    fi
    local cmd
    cmd="$(printf '%q' "cd /home/worker 2>/dev/null; $*")"
    rssh_tty "docker exec -u worker -it '$container' bash -lc $cmd"
}
