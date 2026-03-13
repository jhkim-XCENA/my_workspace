#!/bin/bash
set -euo pipefail

# --- Configuration ---
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mount_dir="$SCRIPT_PATH"
image_name="192.168.57.60:8008/sdk_release/sdk_release:latest"
CLAUDE_BINARY="$HOME/.local/share/claude/versions/2.1.72"
CLAUDE_CONFIG_DIR="$HOME/.claude"
CONTAINER_USER="jhkim"

# --- Validate directories ---
for dir in "$mount_dir/shared" "$mount_dir/sdk_release" "$mount_dir/llvm-project"; do
    if [ ! -d "$dir" ]; then
        echo "$dir does not exist"
        exit 1
    fi
done
echo "$mount_dir will be used as workspace root"

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
TOKEN="$(cat "$SCRIPT_PATH/token.txt" 2>/dev/null | tr -d '[:space:]')"

if [ -z "$TOKEN" ]; then
    echo "Error: token.txt is empty. Please fill in your GitHub token into ${SCRIPT_PATH}/token.txt"
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
  -v "$mount_dir/shared:/shared" \
  -v "$mount_dir/sdk_release:/sdk_release" \
  -v "$mount_dir/llvm-project:/llvm-project" \
  -v "$HOME/.gitconfig:/home/${CONTAINER_USER}/.gitconfig:ro" \
  -v "$HOME/.ssh:/home/${CONTAINER_USER}/.ssh:ro" \
  -v "$HOME/.config/github-copilot:/home/${CONTAINER_USER}/.config/github-copilot" \
  -v "${CLAUDE_BINARY}:/usr/local/bin/claude:ro" \
  -v "${CLAUDE_CONFIG_DIR}/.credentials.json:/home/${CONTAINER_USER}/.claude/.credentials.json" \
  -v "${CLAUDE_CONFIG_DIR}/settings.json:/home/${CONTAINER_USER}/.claude/settings.json" \
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

  # Create user with host UID to match bind mount file ownership
  HOST_UID='"$(id -u)"'
  if ! id "$CUSER" &>/dev/null; then
    useradd -m -s /bin/bash -u "$HOST_UID" "$CUSER" \
      || useradd -m -s /bin/bash -o -u "$HOST_UID" "$CUSER"
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

  # Auto-switch to jhkim when entering as root via "docker exec -it <container> bash"
  echo "if [ \"\$(id -u)\" = \"0\" ] && [ -t 0 ]; then exec su - $CUSER; fi" >> /root/.bashrc
'

# --- Output ---
echo ""
echo "Launched container: $container_name"
echo "  docker exec -it $container_name bash  (auto-switches to ${CONTAINER_USER})"
echo "  Claude Code: claude --dangerously-skip-permissions"
