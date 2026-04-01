#!/bin/bash
set -euo pipefail

# --- Configuration ---
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mount_dir="$SCRIPT_PATH"
SETUP_LOG="$SCRIPT_PATH/setup.log"
: > "$SETUP_LOG"
image_name="192.168.57.60:8008/sdk_release/sdk_release:latest"
CLAUDE_VERSIONS_DIR="$HOME/.local/share/claude/versions"
CLAUDE_BINARY="$CLAUDE_VERSIONS_DIR/$(ls -v "$CLAUDE_VERSIONS_DIR" 2>/dev/null | tail -1)"
CLAUDE_CONFIG_DIR="$HOME/.claude"
CONTAINER_USER="worker"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ============================================================
# Preflight check
# ============================================================
ERRORS=0
pass() { echo -e "  ${GREEN}✔${NC} $1"; }
fail() { echo -e "  ${RED}✘${NC} $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }

echo "=== Preflight check ==="
echo ""

# --- 1. Files & directories ---
echo "[1] 호스트 파일 및 디렉토리"

REQUIRED_DIRS=("$HOME/.ssh" "$CLAUDE_CONFIG_DIR")
REQUIRED_FILES=(
    "$HOME/.gitconfig"
    "$CLAUDE_BINARY"
    "$CLAUDE_CONFIG_DIR/.credentials.json"
    "$HOME/.claude.json"
    "$SCRIPT_PATH/token.txt"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then pass "$dir"; else fail "$dir 디렉토리 없음"; fi
done
for file in "${REQUIRED_FILES[@]}"; do
    if [ -e "$file" ]; then pass "$file"; else fail "$file 파일 없음"; fi
done

TOKEN="$(cat "$SCRIPT_PATH/token.txt" 2>/dev/null | tr -d '[:space:]')"
if [ -n "$TOKEN" ]; then
    pass "token.txt 내용 있음"
else
    fail "token.txt 파일이 없거나 비어있음"
fi

echo ""

# --- 2. Docker ---
echo "[2] Docker"

if command -v docker &>/dev/null; then pass "docker 명령어 존재"; else fail "docker가 설치되지 않음"; fi
if docker info &>/dev/null 2>&1; then pass "docker 데몬 실행 중"; else fail "docker 데몬에 접근 불가"; fi

if docker image inspect "$image_name" &>/dev/null 2>&1; then
    pass "이미지 로컬에 존재"
else
    warn "이미지 로컬에 없음 (pull 시도)"
    if docker pull "$image_name" >> "$SETUP_LOG" 2>&1; then
        pass "이미지 pull 성공"
    else
        fail "이미지 pull 실패: $image_name"
    fi
fi

if [ -e /dev/kvm ]; then pass "/dev/kvm 존재"; else fail "/dev/kvm 없음"; fi

echo ""

# --- Preflight result ---
if [ "$ERRORS" -ne 0 ]; then
    echo -e "${RED}${ERRORS}개 항목 미충족. 위 내용을 확인하세요.${NC}"
    exit 1
fi
echo -e "${GREEN}Preflight 통과${NC}"
echo ""

# ============================================================
# Prepare directories
# ============================================================
parent_dir="$(dirname "$mount_dir")"

clone_if_missing() {
    local dir="$1"
    local repo="$2"
    if [ ! -d "$dir" ]; then
        echo "Cloning $repo ..."
        git clone "https://x-access-token:${TOKEN}@github.com/${repo}.git" "$dir" >> "$SETUP_LOG" 2>&1
    else
        echo "[skip] $repo (already cloned)"
    fi
}

clone_if_missing "$parent_dir/sdk_release"   "xcena-dev/sdk_release"
clone_if_missing "$parent_dir/llvm-project"  "xcena-dev/llvm-project-fork"

# --- Update submodules ---
echo "Updating submodules (sdk_release/tools/pxcc) ..."
git -C "$parent_dir/sdk_release" submodule update --init tools/pxcc >> "$SETUP_LOG" 2>&1

echo "$mount_dir will be used as workspace root"

# ============================================================
# Generate container name
# ============================================================
date_str=$(date +%y%m%d)
container_name="jhkim${date_str}"
if [ "$(docker ps -a -q -f name="^/${container_name}$")" ]; then
    suffix=1
    while [ "$(docker ps -a -q -f name="^/${container_name}_${suffix}$")" ]; do
        suffix=$((suffix + 1))
    done
    container_name="${container_name}_${suffix}"
fi

# ============================================================
# Launch container
# ============================================================
echo "Launching container: $container_name ..."
docker run -dit \
  --name "$container_name" \
  -v "$mount_dir:/home/${CONTAINER_USER}" \
  -v "$HOME/.gitconfig:/home/${CONTAINER_USER}/.gitconfig:ro" \
  -v "$HOME/.ssh:/home/${CONTAINER_USER}/.ssh:ro" \
  -v "${CLAUDE_BINARY}:/usr/local/bin/claude:ro" \
  -v "${CLAUDE_CONFIG_DIR}:/home/${CONTAINER_USER}/.claude" \
  -v "$HOME/.claude.json:/home/${CONTAINER_USER}/.claude.json" \
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
  "$image_name" >> "$SETUP_LOG" 2>&1

# --- Copy repos into container (isolated from host) ---
echo "Copying sdk_release into container ..."
docker cp "$parent_dir/sdk_release" "$container_name":/sdk_release >> "$SETUP_LOG" 2>&1
echo "Copying llvm-project into container ..."
docker cp "$parent_dir/llvm-project" "$container_name":/llvm-project >> "$SETUP_LOG" 2>&1

# ============================================================
# Post-launch: create worker user and bootstrap
# ============================================================
echo "Setting up $CONTAINER_USER user ..."
docker exec "$container_name" bash -c '
  CUSER="worker"
  HOST_UID='"$(id -u)"'

  # Create user with host UID to match bind mount file ownership
  if ! id "$CUSER" &>/dev/null; then
    useradd -m -s /bin/bash -u "$HOST_UID" "$CUSER" \
      || useradd -m -s /bin/bash -o -u "$HOST_UID" "$CUSER"
  fi

  # Ensure .bashrc and .profile exist (useradd skips skel if home already exists)
  for f in .bashrc .profile; do
    if [ ! -f /home/"$CUSER"/$f ]; then
      cp /etc/skel/$f /home/"$CUSER"/$f 2>/dev/null \
        || touch /home/"$CUSER"/$f
    fi
  done

  # Install essential tools (curl, sudo) before user setup runs
  apt-get update -qq
  apt-get install -y -qq curl sudo 2>/dev/null

  # Grant passwordless sudo
  usermod -aG sudo "$CUSER" 2>/dev/null || true
  echo "${CUSER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"$CUSER"
  chmod 440 /etc/sudoers.d/"$CUSER"

  # Fix ownership of home directory and all files inside
  chown -R "$CUSER":"$CUSER" /home/"$CUSER"
  chown -R "$CUSER":"$CUSER" /home/"$CUSER"/.claude 2>/dev/null || true

  # Auto-switch to worker when entering as root
  echo "if [ \"\$(id -u)\" = \"0\" ] && [ -t 0 ]; then exec su - $CUSER; fi" >> /root/.bashrc
' >> "$SETUP_LOG" 2>&1

# --- Switch git remotes to SSH inside container ---
echo "Switching git remotes to SSH ..."
docker exec -u "$CONTAINER_USER" "$container_name" bash -c '
  for repo in /llvm-project /sdk_release /sdk_release/tools/pxcc; do
    if [ -d "$repo/.git" ] || [ -f "$repo/.git" ]; then
      url=$(git -C "$repo" remote get-url origin 2>/dev/null || true)
      if [ -n "$url" ]; then
        ssh_url=$(echo "$url" | sed -E "s|https://[^/]*github.com/|git@github.com:|")
        if [ "$url" != "$ssh_url" ]; then
          git -C "$repo" remote set-url origin "$ssh_url"
          echo "  $repo: $ssh_url"
        fi
      fi
    fi
  done
' >> "$SETUP_LOG" 2>&1

# --- Run execute_with_source.sh as worker inside container ---
echo "Running environment setup inside container ..."
docker exec -u "$CONTAINER_USER" "$container_name" bash -c 'cd ~ && source ./execute_with_source.sh'

# ============================================================
# Output
# ============================================================
echo ""
echo "Launched container: $container_name"
echo "  Detail log: $SETUP_LOG"
echo ""
echo ""
echo "  docker exec -it $container_name bash"
echo ""
echo ""
