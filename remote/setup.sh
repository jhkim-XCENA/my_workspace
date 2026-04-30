#!/bin/bash
# Provision the remote XCENA machine from scratch:
#   1. verify power + SSH (with generous wait — OS may still be booting)
#   2. fresh git clone of my_workspace into a tmp dir
#   3. regenerate config.sh from current shell env (also overwrite local)
#   4. scp the workspace to /home/$REMOTE_USER/my_workspace
#   5. run launch_docker_container.sh on remote (creates container)
#   6. invoke check.sh to verify end-to-end
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/home/worker/remote/lib.sh
source "$SCRIPT_DIR/lib.sh"
load_config || exit 1

REMOTE_DIR="/home/$REMOTE_USER/my_workspace"
TMP_DIR="/tmp/my_workspace.$$"
trap 'rm -rf "$TMP_DIR"' EXIT

# ── 1. Power + SSH (with wait) ──
log_info "[1] Power + SSH check"
if ! is_device_on; then
    log_fail "Remote is OFF. Run reset.sh first."
    exit 1
fi
log_pass "Power: on"
log_info "Waiting for SSH (up to 15 min)..."
if ! wait_for_ssh 900 10; then
    log_fail "SSH did not become reachable within 15 min"
    exit 1
fi
log_pass "SSH: reachable"

# ── 2. Fresh git clone ──
log_info "[2] Cloning my_workspace to $TMP_DIR"
if ! git clone --depth 1 git@github.com:jhkim-XCENA/my_workspace.git "$TMP_DIR"; then
    log_fail "git clone failed"
    exit 1
fi
log_pass "Cloned"

# ── 3. Generate config.sh from current shell env ──
log_info "[3] Writing config.sh from current shell env"
cat > "$TMP_DIR/config.sh" <<EOF
GH_TOKEN=${GH_TOKEN:-}
CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN:-}
REMOTE_IP=${REMOTE_IP}
REMOTE_USER=${REMOTE_USER}
REMOTE_PASSWORD=${REMOTE_PASSWORD}
EOF
chmod 600 "$TMP_DIR/config.sh"
# Sync local config.sh to match (so local env and remote stay aligned)
cp "$TMP_DIR/config.sh" "$WORKSPACE_DIR/config.sh"
chmod 600 "$WORKSPACE_DIR/config.sh"
log_pass "config.sh written (local + tmp)"

# ── 4. Sync SSH keys to remote ──
# launch_docker_container.sh requires /home/$REMOTE_USER/.ssh to exist (for the
# -v ssh mount into the container, which the container uses for git clone).
# A fresh remote user may have no .ssh dir yet — sync our local keys.
log_info "[4] Syncing SSH keys to remote /home/$REMOTE_USER/.ssh"
rssh "mkdir -p /home/$REMOTE_USER/.ssh && chmod 700 /home/$REMOTE_USER/.ssh" \
    || { log_fail "mkdir .ssh on remote failed"; exit 1; }
for f in id_ed25519 id_ed25519.pub known_hosts; do
    if [ -f "$HOME/.ssh/$f" ]; then
        rscp "$HOME/.ssh/$f" "$(RHOST):/home/$REMOTE_USER/.ssh/" >/dev/null \
            || log_warn "  scp $f failed"
    fi
done
rssh "[ -f /home/$REMOTE_USER/.ssh/id_ed25519 ] && chmod 600 /home/$REMOTE_USER/.ssh/id_ed25519 || true" >/dev/null 2>&1
log_pass "SSH keys synced"

# ── 5. SCP workspace to remote ──
# Wipe-and-recreate to ensure idempotency: a previous setup.sh run can leave
# read-only git pack files behind, which scp cannot overwrite (Permission
# denied). Provisioning means fresh state, so rm -rf is the right semantic.
log_info "[5] Syncing $TMP_DIR to $(RHOST):$REMOTE_DIR"
rssh "rm -rf '$REMOTE_DIR' && mkdir -p '$REMOTE_DIR'" \
    || { log_fail "wipe/mkdir on remote failed"; exit 1; }
# scp -r src/. dst/  copies contents (including dotfiles via the trailing /.)
if ! rscp "$TMP_DIR/." "$(RHOST):$REMOTE_DIR/"; then
    log_fail "scp failed"
    exit 1
fi
log_pass "Workspace synced"

# ── 6. Launch container on remote ──
log_info "[6] Running launch_docker_container.sh on remote (this can take several minutes)"
if ! rssh "cd '$REMOTE_DIR' && source ./launch_docker_container.sh"; then
    log_fail "launch_docker_container.sh failed on remote"
    exit 1
fi
log_pass "Container launched"

# ── 7. Verify with check.sh ──
log_info "[7] Running check.sh"
if bash "$SCRIPT_DIR/check.sh"; then
    log_pass "setup.sh complete"
else
    log_fail "check.sh failed after setup — investigate manually"
    exit 1
fi
