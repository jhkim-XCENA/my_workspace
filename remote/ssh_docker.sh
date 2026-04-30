#!/bin/bash
# Run a command inside the latest jhkim_ container on the remote machine.
# Usage:
#   ssh_docker.sh <command string>
#   ssh_docker.sh "xcena_cli num-device"
#   ssh_docker.sh "cd /home/worker/sort && ./build.sh"
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/home/worker/remote/lib.sh
source "$SCRIPT_DIR/lib.sh"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <command string>" >&2
    echo "Example: $0 'xcena_cli num-device'" >&2
    exit 1
fi

load_config || exit 1
rdocker_exec_tty "$*"
