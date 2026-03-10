#!/bin/bash
set -euo pipefail

# --- Configuration ---
mount_dir="/home/jhkim/shared"
image_name="192.168.57.60:8008/sdk_release/xcena_sdk_81c21@sha256:cd848f566914203014e8dcf0b07f0c9bff7b3d2c13079df0c705e0b065ed95fc"
CLAUDE_BINARY="$HOME/.local/share/claude/versions/2.1.72"
CLAUDE_CONFIG_DIR="$HOME/.claude"
CONTAINER_USER="jhkim"

# --- Validate mount dir ---
if [ -d "$mount_dir" ]; then
    echo "$mount_dir will be mounted as /shared in the container"
else
    echo "$mount_dir does not exist"
    exit 1
fi

# --- Validate Claude Code ---
if [ ! -f "$CLAUDE_BINARY" ]; then
    echo "Claude Code binary not found: $CLAUDE_BINARY"
    exit 1
fi
if [ ! -f "$CLAUDE_CONFIG_DIR/.credentials.json" ]; then
    echo "Claude Code credentials not found: $CLAUDE_CONFIG_DIR/.credentials.json"
    exit 1
fi

# --- Read GitHub token (for GitHub Copilot CLI) ---
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKEN="$(cat "$SCRIPT_PATH/token.txt" 2>/dev/null || true)"

if [ -z "$TOKEN" ]; then
    echo "fill your token into ${SCRIPT_PATH}/token.txt"
    exit 1
fi

# --- Generate container name: jhkim{yymmdd} ---
date_str=$(date +%y%m%d)
container_name="jhkim${date_str}"
# if container exists, add a suffix number
if [ "$(docker ps -a -q -f name="^/${container_name}$")" ]; then
    suffix=1
    while [ "$(docker ps -a -q -f name="^/${container_name}_${suffix}$")" ]; do
        suffix=$((suffix + 1))
    done
    container_name="${container_name}_${suffix}"
fi

# --- Launch container ---
docker run -dit \
  --name "$container_name" \
  -v "/home/jhkim/shared:/shared" \
  -v "$HOME/.gitconfig:/home/${CONTAINER_USER}/.gitconfig:ro" \
  -v "$HOME/.ssh:/home/${CONTAINER_USER}/.ssh:ro" \
  -v "$HOME/.config/github-copilot:/home/${CONTAINER_USER}/.config/github-copilot" \
  -v "${CLAUDE_BINARY}:/usr/local/bin/claude:ro" \
  -v "${CLAUDE_CONFIG_DIR}/.credentials.json:/home/${CONTAINER_USER}/.claude/.credentials.json:ro" \
  -v "${CLAUDE_CONFIG_DIR}/settings.json:/home/${CONTAINER_USER}/.claude/settings.json:ro" \
  -e GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
  -e GIT_AUTHOR_NAME="jhkim-XCENA" \
  -e GIT_AUTHOR_EMAIL="jeongho.kim@xcena.com" \
  -e GIT_COMMITTER_NAME="jhkim-XCENA" \
  -e GIT_COMMITTER_EMAIL="jeongho.kim@xcena.com" \
  -e GITHUB_TOKEN="$TOKEN" \
  -e USER="$CONTAINER_USER" \
  -e LANG=C.UTF-8 \
  -e LC_ALL=C.UTF-8 \
  --device=/dev/kvm \
  --cap-add=SYS_ADMIN \
  "$image_name"

# --- Post-launch: create non-root user with sudo ---
docker exec "$container_name" bash -c '
  CUSER="jhkim"

  # Create user (skip if already exists)
  if ! id "$CUSER" &>/dev/null; then
    useradd -m -s /bin/bash -u 1000 "$CUSER"
  fi

  # Install sudo if not available
  if ! command -v sudo &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq sudo 2>/dev/null \
      || yum install -y sudo 2>/dev/null \
      || true
  fi

  # Grant passwordless sudo
  usermod -aG sudo "$CUSER" 2>/dev/null || true
  echo "${CUSER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"$CUSER"
  chmod 440 /etc/sudoers.d/"$CUSER"

  # Fix ownership of home directory and mounted config dirs
  chown "$CUSER":"$CUSER" /home/"$CUSER"
  chown -R "$CUSER":"$CUSER" /home/"$CUSER"/.claude 2>/dev/null || true
  mkdir -p /home/"$CUSER"/.config
  chown -R "$CUSER":"$CUSER" /home/"$CUSER"/.config 2>/dev/null || true
'

# --- Output ---
echo ""
echo "Launched container: $container_name"
echo "  docker exec -it -u ${CONTAINER_USER} -w /shared $container_name bash"
echo "  Claude Code: claude --dangerously-skip-permissions"
