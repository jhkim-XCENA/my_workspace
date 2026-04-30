#!/bin/bash

# source로 실행 강제
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "this script should be executed like: source ./launch_docker_container.sh"
    exit 1
fi

# --- Parse arguments ---
LAUNCH_MODE="sdk_release"
for arg in "$@"; do
    case "$arg" in
        --db-devenv) LAUNCH_MODE="db_devenv" ;;
    esac
done

# --- Configuration ---
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mount_dir="$SCRIPT_PATH"
SETUP_LOG="$SCRIPT_PATH/setup.log"
: > "$SETUP_LOG"
CONTAINER_USER="worker"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
GRAY='\033[0;90m'
NC='\033[0m'

# --- Timing & logging helpers ---
TOTAL_START=$SECONDS
_ts() { printf "${GRAY}[%02d:%02d]${NC}" $(( (SECONDS - TOTAL_START) / 60 )) $(( (SECONDS - TOTAL_START) % 60 )); }
_elapsed() { local d=$((SECONDS - $1)); printf "%dm %ds" $((d/60)) $((d%60)); }

log_done()    { echo -e "$(_ts)${GREEN}[done]${NC} $1"; }
log_skip()    { echo -e "$(_ts)${GREEN}[skip]${NC} $1"; }
log_install() { echo -e "$(_ts)${YELLOW}[install]${NC} $1"; }
log_info()    { echo -e "$(_ts) $1"; }
log_pass()    { echo -e "$(_ts)${GREEN}[ok]${NC} $1"; }
log_fail()    { echo -e "$(_ts)${RED}[fail]${NC} $1"; ERRORS=$((ERRORS + 1)); }
log_warn()    { echo -e "$(_ts)${YELLOW}[warn]${NC} $1"; }

STEP=0
log_section() { STEP=$((STEP+1)); echo -e "\n$(_ts) === [Step $STEP] $1 ==="; }

# ============================================================
# Preflight check
# ============================================================
ERRORS=0

log_section "Preflight"

# --- 1. Files & directories ---
log_info "[1] 호스트 파일 및 디렉토리"

REQUIRED_DIRS=("$HOME/.ssh")
REQUIRED_FILES=(
    "$SCRIPT_PATH/config.sh"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then log_pass "$dir"; else log_fail "$dir 디렉토리 없음"; fi
done
for file in "${REQUIRED_FILES[@]}"; do
    if [ -e "$file" ]; then log_pass "$file"; else log_fail "$file 파일 없음"; fi
done

TOKEN=""
CLAUDE_TOKEN=""
if [ -f "$SCRIPT_PATH/config.sh" ]; then
    source "$SCRIPT_PATH/config.sh"
    TOKEN="$GH_TOKEN"
    CLAUDE_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN"
fi

if [ -n "$TOKEN" ]; then
    log_pass "config.sh: GH_TOKEN 내용 있음"
else
    log_fail "config.sh: GH_TOKEN 이 비어있음"
fi

if [ -n "$CLAUDE_TOKEN" ]; then
    log_pass "config.sh: CLAUDE_CODE_OAUTH_TOKEN 내용 있음"
else
    log_fail "config.sh: CLAUDE_CODE_OAUTH_TOKEN 이 비어있음"
fi

if [ -n "$REMOTE_IP" ];       then log_pass "config.sh: REMOTE_IP 내용 있음 ($REMOTE_IP)"; else log_warn "config.sh: REMOTE_IP 이 비어있음"; fi
if [ -n "$REMOTE_USER" ];     then log_pass "config.sh: REMOTE_USER 내용 있음 ($REMOTE_USER)"; else log_warn "config.sh: REMOTE_USER 이 비어있음"; fi
if [ -n "$REMOTE_PASSWORD" ]; then log_pass "config.sh: REMOTE_PASSWORD 내용 있음"; else log_warn "config.sh: REMOTE_PASSWORD 이 비어있음"; fi

# --- 2. Docker ---
log_info "[2] Docker"

if command -v docker &>/dev/null; then log_pass "docker 명령어 존재"; else log_fail "docker가 설치되지 않음"; fi
if docker info &>/dev/null 2>&1; then log_pass "docker 데몬 실행 중"; else log_fail "docker 데몬에 접근 불가"; fi

# --- xcena_cli device detection ---
DEVICE_COUNT=0
USE_KVM=true
if command -v xcena_cli &>/dev/null; then
    DEVICE_COUNT=$(xcena_cli num-device 2>/dev/null | grep -oP 'Number of devices : \K[0-9]+' || echo "0")
    log_pass "xcena_cli 존재 (디바이스 ${DEVICE_COUNT}개 감지)"
    if [ "$DEVICE_COUNT" -ge 1 ]; then
        USE_KVM=false
        log_warn "디바이스 ${DEVICE_COUNT}개 감지 → silicon 모드"
    else
        log_pass "디바이스 없음 → qemu 모드 (/dev/kvm 사용)"
    fi
else
    log_warn "xcena_cli 없음 → qemu 모드로 진행"
fi

if [ "$USE_KVM" = true ]; then
    if [ -e /dev/kvm ]; then log_pass "/dev/kvm 존재"; else log_fail "/dev/kvm 없음"; fi
fi

# --- Preflight result ---
if [ "$ERRORS" -ne 0 ]; then
    log_fail "${ERRORS}개 항목 미충족. 위 내용을 확인하세요."
    return 1
fi
log_pass "Preflight 통과"

# ============================================================
# Mode-specific setup (db-devenv repo & image)
# ============================================================
if [ "$LAUNCH_MODE" = "db_devenv" ]; then
    log_section "Mode: db-devenv"
    DB_DEVENV_DIR="$SCRIPT_PATH/db-devenv"

    # db-devenv 레포 clone 또는 업데이트
    _t=$SECONDS
    if [ ! -d "$DB_DEVENV_DIR" ]; then
        log_install "db-devenv clone"
        GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
            git clone "git@github.com:xcena-dev/db-devenv.git" "$DB_DEVENV_DIR" >> "$SETUP_LOG" 2>&1
        log_done "db-devenv clone ($(_elapsed $_t))"
    else
        log_install "db-devenv pull"
        git -C "$DB_DEVENV_DIR" pull >> "$SETUP_LOG" 2>&1
        log_done "db-devenv pull ($(_elapsed $_t))"
    fi

    # db-devenv tag 계산으로 이미지 결정
    log_info "Computing devenv image tag ..."
    eval "$(bash "$DB_DEVENV_DIR/scripts/docker-image-build.sh" registry tags 2>>"$SETUP_LOG")"
    image_name="${DOCKER_REGISTRY}/${DEVENV_IMAGE_NAME}:${DEVENV_TAG}"
    log_info "Image: $image_name"
else
    image_name="192.168.57.60:8008/sdk_release/sdk_release:latest"
fi

# --- Docker 이미지 확인/pull (항상 최신 pull 시도) ---
log_info "[3] Docker 이미지"
HAS_LOCAL_IMAGE=false
if docker image inspect "$image_name" &>/dev/null 2>&1; then
    HAS_LOCAL_IMAGE=true
    log_pass "이미지 로컬에 존재: $image_name"
fi

log_install "이미지 pull (최신 확인): $image_name"
_t=$SECONDS
if docker pull "$image_name" >> "$SETUP_LOG" 2>&1; then
    log_done "이미지 pull ($(_elapsed $_t))"
elif [ "$HAS_LOCAL_IMAGE" = true ]; then
    log_warn "이미지 pull 실패 — 로컬 이미지로 진행 ($(_elapsed $_t))"
else
    log_fail "이미지 pull 실패 & 로컬에도 없음: $image_name"
    return 1
fi

# ============================================================
# Generate container name and session directory
# ============================================================
date_str=$(date +%y%m%d)
if [ "$USE_KVM" = true ]; then
    mode="qemu"
else
    mode="silicon"
fi

if [ "$LAUNCH_MODE" = "db_devenv" ]; then
    type_prefix="db"
else
    type_prefix="sdk"
fi

session_base="$SCRIPT_PATH/jhkim_${type_prefix}_${mode}"
container_name="jhkim_${type_prefix}_${mode}_${date_str}"
session_dir="${session_base}/${type_prefix}_${mode}_${date_str}"

if [ "$(docker ps -a -q -f name="^/${container_name}$")" ] || [ -d "$session_dir" ]; then
    suffix=1
    while [ "$(docker ps -a -q -f name="^/${container_name}_${suffix}$")" ] || [ -d "${session_dir}_${suffix}" ]; do
        suffix=$((suffix + 1))
    done
    container_name="${container_name}_${suffix}"
    session_dir="${session_dir}_${suffix}"
fi

mkdir -p "$session_dir"
log_info "Session: $session_dir"

# ============================================================
# Clone repos (shallow, SSH)
# ============================================================
log_section "Clone repos (host → session dir)"

clone_if_missing() {
    local dir="$1"
    local repo="$2"
    if [ ! -d "$dir" ]; then
        log_install "$repo"
        local _t=$SECONDS
        GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
            git clone --depth 1 "git@github.com:${repo}.git" "$dir" >> "$SETUP_LOG" 2>&1
        log_done "$repo ($(_elapsed $_t))"
    else
        log_skip "$repo (already cloned)"
    fi
}

clone_if_missing "$session_dir/sdk_release"   "xcena-dev/sdk_release"
clone_if_missing "$session_dir/llvm-project"  "xcena-dev/llvm-project-fork"

# --- Update submodules ---
_t=$SECONDS
log_install "submodule: sdk_release/tools/pxcc"
GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
    git -C "$session_dir/sdk_release" submodule update --init tools/pxcc >> "$SETUP_LOG" 2>&1
log_done "submodule: pxcc ($(_elapsed $_t))"

# --- Advance pxcc to latest origin/main (submodule pinned commit 무시) ---
_t=$SECONDS
log_install "pxcc → origin/main"
GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
    git -C "$session_dir/sdk_release/tools/pxcc" fetch origin main >> "$SETUP_LOG" 2>&1
git -C "$session_dir/sdk_release/tools/pxcc" checkout origin/main >> "$SETUP_LOG" 2>&1
log_done "pxcc → origin/main ($(_elapsed $_t))"

# --- db-devenv 모드: microbenchmark clone + submodule ---
if [ "$LAUNCH_MODE" = "db_devenv" ]; then
    clone_if_missing "$session_dir/microbenchmark" "xcena-dev/microbenchmark"

    _t=$SECONDS
    log_install "submodule: microbenchmark (recursive)"
    GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
        git -C "$session_dir/microbenchmark" submodule update --init --recursive >> "$SETUP_LOG" 2>&1
    log_done "submodule: microbenchmark ($(_elapsed $_t))"
fi

# ============================================================
# Launch container
# ============================================================
log_section "Launch container ($container_name, ${type_prefix}/${mode})"
log_info "[docker outside] docker run 및 볼륨 마운트"
_t=$SECONDS

DOCKER_KVM_OPTS=()
if [ "$LAUNCH_MODE" = "db_devenv" ]; then
    # db-devenv 가이드라인: 항상 privileged + SYS_ADMIN
    DOCKER_KVM_OPTS+=(--privileged --cap-add=SYS_ADMIN)
elif [ "$USE_KVM" = true ]; then
    DOCKER_KVM_OPTS+=(--device=/dev/kvm --cap-add=SYS_ADMIN)
else
    DOCKER_KVM_OPTS+=(--privileged --cap-add=SYS_ADMIN)
fi

# Silicon mode: containers must mount /tmp/pxl so xcena_cli can talk to the
# host pxl_resourced daemon (XCENA Resource Management Daemon). Per the
# multi-container guide (sdk_release/docs/install/docker/multiple-containers.md),
# containers also need --pid=host and --userns=host so xcena_cli can resolve
# the daemon's PID-scoped resources. Without these, `xcena_cli num-device`
# reports "No CXL devices found" even with --privileged + /tmp/pxl mounted.
DOCKER_PXL_OPTS=()
if [ "$USE_KVM" = false ] && [ -d /tmp/pxl ]; then
    DOCKER_PXL_OPTS+=(--pid=host --userns=host -v /tmp/pxl:/tmp/pxl)
fi

# db-devenv 추가 볼륨/옵션
DOCKER_EXTRA_OPTS=()
if [ "$LAUNCH_MODE" = "db_devenv" ]; then
    DOCKER_EXTRA_OPTS+=(
        --entrypoint bash
        -v "$session_dir/microbenchmark:/microbenchmark"
        -v "$DB_DEVENV_DIR/scripts/runtime:/opt/db-devenv/runtime"
        -v "$DB_DEVENV_DIR/config/hooks:/opt/db-devenv/hooks"
    )
    # Cargo 캐시 (호스트 디렉토리 사전 생성)
    mkdir -p "$HOME/.cargo/registry" "$HOME/.cargo/git"
    DOCKER_EXTRA_OPTS+=(
        -v "$HOME/.cargo/registry:/home/${CONTAINER_USER}/.cargo/registry"
        -v "$HOME/.cargo/git:/home/${CONTAINER_USER}/.cargo/git"
    )
fi

docker run -dit \
  --name "$container_name" \
  --user root \
  --network=host \
  -v "$mount_dir:/home/${CONTAINER_USER}" \
  -v "$HOME/.ssh:/home/${CONTAINER_USER}/.ssh" \
  -v "$session_dir/sdk_release:/sdk_release" \
  -v "$session_dir/llvm-project:/llvm-project" \
  -e GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
  -e GITHUB_TOKEN="$TOKEN" \
  -e CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_TOKEN" \
  -e CONTAINER_NAME="$container_name" \
  -e USER="$CONTAINER_USER" \
  -e LANG=C.UTF-8 \
  -e LC_ALL=C.UTF-8 \
  "${DOCKER_KVM_OPTS[@]}" \
  "${DOCKER_PXL_OPTS[@]}" \
  "${DOCKER_EXTRA_OPTS[@]}" \
  "$image_name" >> "$SETUP_LOG" 2>&1
log_done "docker run ($(_elapsed $_t))"

# --- 컨테이너 → 호스트 SSH 허용 (공개키를 호스트 authorized_keys에 등록) ---
PUBKEY=$(cat "$HOME/.ssh/id_ed25519.pub" 2>/dev/null || true)
if [ -n "$PUBKEY" ]; then
    AUTH_KEYS="$HOME/.ssh/authorized_keys"
    touch "$AUTH_KEYS" && chmod 600 "$AUTH_KEYS"
    if ! grep -qF "$PUBKEY" "$AUTH_KEYS" 2>/dev/null; then
        echo "$PUBKEY" >> "$AUTH_KEYS"
        log_done "host SSH authorized_keys 등록"
    else
        log_skip "host SSH authorized_keys (이미 등록됨)"
    fi
else
    log_warn "id_ed25519.pub 없음 — 수동으로 authorized_keys 설정 필요"
fi

# ============================================================
# Post-launch: create worker user and bootstrap (단계별 타이밍)
# ============================================================
log_section "Container init [docker inside]"

# --- 1. User 생성 ---
_t=$SECONDS
log_install "user 생성 (worker, UID=$(id -u))"
docker exec "$container_name" bash -c '
  CUSER="worker"
  HOST_UID='"$(id -u)"'
  EXISTING=$(getent passwd "$HOST_UID" | cut -d: -f1 || true)
  if [ -n "$EXISTING" ] && [ "$EXISTING" != "$CUSER" ]; then
    userdel "$EXISTING" 2>/dev/null || true
  fi
  if ! id "$CUSER" &>/dev/null; then
    useradd -m -s /bin/bash -u "$HOST_UID" "$CUSER"
  fi
  for f in .bashrc .profile; do
    if [ ! -f /home/"$CUSER"/$f ]; then
      cp /etc/skel/$f /home/"$CUSER"/$f 2>/dev/null || touch /home/"$CUSER"/$f
    fi
  done
' >> "$SETUP_LOG" 2>&1
log_done "user 생성 ($(_elapsed $_t))"

# --- 2. apt-get: curl, sudo, git (이미 있으면 skip) ---
_t=$SECONDS
APT_NEEDED=$(docker exec "$container_name" bash -c '
  missing=0
  command -v curl &>/dev/null || missing=1
  command -v sudo &>/dev/null || missing=1
  command -v git  &>/dev/null || missing=1
  echo $missing
')
if [ "$APT_NEEDED" = "0" ]; then
    log_skip "apt (curl, sudo, git 이미 설치됨)"
else
    log_install "apt update + install (curl, sudo, git)"
    docker exec "$container_name" bash -c '
      apt-get update -qq
      apt-get install -y -qq curl sudo git 2>/dev/null
    ' >> "$SETUP_LOG" 2>&1
    log_done "apt install ($(_elapsed $_t))"
fi

# --- 3. sudo 설정 ---
_t=$SECONDS
log_install "sudo 설정"
docker exec "$container_name" bash -c '
  CUSER="worker"
  usermod -aG sudo "$CUSER" 2>/dev/null || true
  echo "${CUSER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"$CUSER"
  chmod 440 /etc/sudoers.d/"$CUSER"
' >> "$SETUP_LOG" 2>&1
log_done "sudo 설정 ($(_elapsed $_t))"

# --- 4. chown (home directory) ---
_t=$SECONDS
log_install "chown /home/$CONTAINER_USER"
docker exec "$container_name" bash -c '
  chown -R worker:worker /home/worker 2>/dev/null || true
' >> "$SETUP_LOG" 2>&1
log_done "chown ($(_elapsed $_t))"

# --- 5. root → worker 자동 전환 ---
_t=$SECONDS
docker exec "$container_name" bash -c '
  echo "if [ \"\$(id -u)\" = \"0\" ] && [ -t 0 ]; then exec su - worker; fi" >> /root/.bashrc
' >> "$SETUP_LOG" 2>&1
log_done "root auto-switch ($(_elapsed $_t))"

# --- Switch git remotes to SSH inside container ---
_t=$SECONDS
log_install "git remote → SSH"
if [ "$LAUNCH_MODE" = "db_devenv" ]; then
    GIT_REPOS="/llvm-project /sdk_release /sdk_release/tools/pxcc /microbenchmark"
else
    GIT_REPOS="/llvm-project /sdk_release /sdk_release/tools/pxcc"
fi
docker exec -u "$CONTAINER_USER" "$container_name" bash -c '
  for repo in '"$GIT_REPOS"'; do
    if [ -d "$repo/.git" ] || [ -f "$repo/.git" ]; then
      url=$(git -C "$repo" remote get-url origin 2>/dev/null || true)
      if [ -n "$url" ]; then
        ssh_url=$(echo "$url" | sed -E "s|https://[^/]*github.com/|git@github.com:|")
        if [ "$url" != "$ssh_url" ]; then
          git -C "$repo" remote set-url origin "$ssh_url"
        fi
      fi
    fi
  done
' >> "$SETUP_LOG" 2>&1
log_done "git remote → SSH ($(_elapsed $_t))"

# --- Switch home repo remote to HTTPS (SSH key identity mismatch) ---
docker exec -u "$CONTAINER_USER" "$container_name" bash -c '
  cd ~ && url=$(git remote get-url origin 2>/dev/null || true)
  if [ -n "$url" ]; then
    https_url=$(echo "$url" | sed -E "s|git@github.com:|https://github.com/|")
    if [ "$url" != "$https_url" ]; then
      git remote set-url origin "$https_url"
    fi
  fi
' >> "$SETUP_LOG" 2>&1

# --- Run execute_with_source.sh as worker inside container ---
log_section "Environment bootstrap [docker inside] (execute_with_source.sh)"
_t=$SECONDS
docker exec -u "$CONTAINER_USER" "$container_name" bash -c 'cd ~ && source ./execute_with_source.sh'
log_done "execute_with_source.sh ($(_elapsed $_t))"

# ============================================================
# xcena_cli sanity check + legacy fallback
# ============================================================
# In silicon mode, the SDK's xcena_cli (currently 1.4.5) may report 0 devices
# even when the host stack (driver + libpxl + pxl_resourced) is healthy and
# /dev/mx_dma is populated correctly. The older xcena_cli binary baked into
# the db-devenv image enumerates devices fine on the same host, so we keep it
# checked into binaries/xcena_cli.legacy as a workaround until the SDK's
# xcena_cli is fixed upstream.
LEGACY_CLI="$SCRIPT_PATH/binaries/xcena_cli.legacy"
if [ "$USE_KVM" = false ] && [ -f "$LEGACY_CLI" ]; then
    log_section "xcena_cli sanity check"
    _t=$SECONDS
    cli_n="$(docker exec -u "$CONTAINER_USER" "$container_name" \
        bash -lc 'xcena_cli num-device 2>/dev/null | grep -oP "Number of devices : \K[0-9]+" || echo 0' 2>/dev/null \
        | tr -d '[:space:]')"
    if [ -z "$cli_n" ] || [ "$cli_n" = "0" ]; then
        log_warn "xcena_cli num-device → 0 inside container — applying legacy binary workaround"
        log_warn "  TODO: drop this workaround once SDK ships an xcena_cli that re-detects devices"
        docker cp "$LEGACY_CLI" "$container_name:/usr/local/bin/xcena_cli" >> "$SETUP_LOG" 2>&1
        docker exec -u root "$container_name" chmod +x /usr/local/bin/xcena_cli >> "$SETUP_LOG" 2>&1
        cli_n2="$(docker exec -u "$CONTAINER_USER" "$container_name" \
            bash -lc 'xcena_cli num-device 2>/dev/null | grep -oP "Number of devices : \K[0-9]+" || echo 0' 2>/dev/null \
            | tr -d '[:space:]')"
        if [ "${cli_n2:-0}" -ge 1 ] 2>/dev/null; then
            log_done "legacy xcena_cli detects $cli_n2 device(s) ($(_elapsed $_t))"
        else
            log_fail "legacy xcena_cli also reports 0 devices — host driver/daemon may be unhealthy"
        fi
    else
        log_pass "xcena_cli detects $cli_n device(s) — no workaround needed"
    fi
fi

# ============================================================
# Register docker alias
# ============================================================
BASHRC_FILE="$HOME/.bashrc"

if [ "$LAUNCH_MODE" = "db_devenv" ]; then
    ALIAS_NAME="docker_db_exec"
else
    ALIAS_NAME="docker_exec"
fi
ALIAS_LINE="alias ${ALIAS_NAME}='docker exec -u $CONTAINER_USER -w /home/$CONTAINER_USER -it $container_name bash'"

if grep -q "^alias ${ALIAS_NAME}=" "$BASHRC_FILE"; then
    sed -i "s|^alias ${ALIAS_NAME}=.*|${ALIAS_LINE}|" "$BASHRC_FILE"
else
    echo "$ALIAS_LINE" >> "$BASHRC_FILE"
fi

source "$BASHRC_FILE"

# ============================================================
# Output
# ============================================================
echo ""
log_done "Complete: $container_name (${type_prefix}/${mode}, total: $(_elapsed $TOTAL_START))"
log_info "Detail log: $SETUP_LOG"
echo ""
log_info "${ALIAS_NAME} 를 실행하여 컨테이너에 접속하세요."
echo ""
