#!/bin/bash
# Incremental rsync of local /home/worker tracked files → remote
# /home/$REMOTE_USER/my_workspace. Faster than setup.sh's wipe-and-recreate
# for in-progress development (no git push needed to test on remote).
#
# Excludes: nvim/nvim, lazy-lock.json, sdk_release/, llvm-project/, shared/,
# tokens, logs, backups (mirrors .gitignore semantics + a few obvious extras).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/home/worker/remote/lib.sh
source "$SCRIPT_DIR/lib.sh"
load_config || exit 1

if ! command -v rsync >/dev/null 2>&1; then
    log_fail "rsync not installed locally — run: sudo apt-get install -y rsync"
    exit 1
fi

REMOTE_DIR="/home/$REMOTE_USER/my_workspace"

log_info "rsync $WORKSPACE_DIR/ → $(RHOST):$REMOTE_DIR/"
rssh "mkdir -p '$REMOTE_DIR'" || { log_fail "remote mkdir failed"; exit 1; }

# rsync via sshpass — quote the entire ssh command to pass through password
RSYNC_RSH="sshpass -p $REMOTE_PASSWORD ssh -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR"

rsync -avz --delete-excluded \
    --exclude='.git/' \
    --exclude='nvim/nvim' \
    --exclude='nvim/lazy-lock.json' \
    --exclude='sdk_release/' \
    --exclude='llvm-project/' \
    --exclude='shared/' \
    --exclude='*.bak_*' \
    --exclude='*.bak' \
    --exclude='setup.log' \
    --exclude='.bash_history' \
    --exclude='.lesshst' \
    --exclude='.cache/' \
    --exclude='.npm/' \
    --exclude='.local/' \
    --exclude='.config/' \
    --exclude='.claude/' \
    --exclude='.claude.json' \
    --exclude='.gitconfig' \
    --exclude='.ssh/' \
    --exclude='xvector-dev/' \
    --exclude='confluence_docs/' \
    --exclude='cost_model/' \
    --exclude='eac_chapters/' \
    --exclude='wilson_chapters/' \
    --exclude='uarch/' \
    --exclude='mu_llvm-*/' \
    --exclude='*.pdf' \
    -e "$RSYNC_RSH" \
    "$WORKSPACE_DIR/" "$(RHOST):$REMOTE_DIR/" \
    || { log_fail "rsync failed"; exit 1; }

log_pass "synced"
