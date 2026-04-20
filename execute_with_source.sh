#!/bin/bash

# 현재 스크립트를 source ./execute_with_source.sh 형태로 실행했는지 검사
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "this script should be executed like: source ./execute_with_source.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_LOG="$SCRIPT_DIR/setup.log"
: > "$SETUP_LOG"

SUDO=""
if [[ $EUID -ne 0 ]]; then
    SUDO="sudo"
fi

# apt: debconf 경고 억제
export DEBIAN_FRONTEND=noninteractive

# db-devenv 이미지의 nvm 로드 (node가 /opt/nvm에 설치되어 PATH에 없는 경우)
if [ -s "${NVM_DIR:-/opt/nvm}/nvm.sh" ]; then
    export NVM_DIR="${NVM_DIR:-/opt/nvm}"
    . "$NVM_DIR/nvm.sh"
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m'

# --- Timing & logging helpers ---
TOTAL_START=$SECONDS
_ts()      { printf "${GRAY}[%02d:%02d]${NC}" $(( (SECONDS - TOTAL_START) / 60 )) $(( (SECONDS - TOTAL_START) % 60 )); }
_elapsed() { local d=$((SECONDS - $1)); printf "%dm %ds" $((d/60)) $((d%60)); }

log_done()    { echo -e "$(_ts)${GREEN}[done]${NC} $1"; }
log_skip()    { echo -e "$(_ts)${GREEN}[skip]${NC} $1"; }
log_install() { echo -e "$(_ts)${YELLOW}[install]${NC} $1"; }
log_info()    { echo -e "$(_ts) $1"; }
log_pass()    { echo -e "$(_ts)${GREEN}[ok]${NC} $1"; }
log_fail()    { echo -e "$(_ts)${RED}[fail]${NC} $1"; }
log_warn()    { echo -e "$(_ts)${YELLOW}[warn]${NC} $1"; }

STEP=0
log_section() { STEP=$((STEP+1)); echo -e "\n$(_ts) === [Step $STEP] $1 ==="; }

# --- Install helpers ---

# ensure_cmd <command> <min_major_version> <install_function>
ensure_cmd() {
    local cmd="$1" min_ver="$2" install_fn="$3"
    if command -v "$cmd" &> /dev/null; then
        local cur_ver
        cur_ver="$("$cmd" --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+' | head -1)"
        local cur_major="${cur_ver%%.*}"
        if [ -n "$cur_major" ] && [ "$cur_major" -ge "$min_ver" ] 2>/dev/null; then
            log_skip "$cmd (v$cur_ver >= v$min_ver)"
            return 0
        fi
    fi
    log_install "$cmd (requires v$min_ver+)"
    local _t=$SECONDS
    "$install_fn" >> "$SETUP_LOG" 2>&1
    log_done "$cmd ($(_elapsed $_t))"
}

# ensure_pkg <package_name> [command_name]
ensure_pkg() {
    local pkg="$1" cmd="${2:-$1}"
    if command -v "$cmd" &> /dev/null || dpkg -s "$pkg" &> /dev/null 2>&1; then
        log_skip "$pkg"
        return 0
    fi
    log_install "$pkg"
    local _t=$SECONDS
    $SUDO apt install -y "$pkg" >> "$SETUP_LOG" 2>&1
    log_done "$pkg ($(_elapsed $_t))"
}

# ensure_npm <package_name>
ensure_npm() {
    local pkg="$1"
    if npm list -g "$pkg" &> /dev/null; then
        log_skip "npm:$pkg"
        return 0
    fi
    log_install "npm:$pkg"
    local _t=$SECONDS
    npm install -g "$pkg" >> "$SETUP_LOG" 2>&1
    log_done "npm:$pkg ($(_elapsed $_t))"
}

# --- Install functions ---
install_node() { bash "$SCRIPT_DIR/third_party/install_node.sh"; }
install_gh()   { bash "$SCRIPT_DIR/third_party/install_gh.sh"; }

# ============================================================
# Main
# ============================================================
log_info "Setup log: $SETUP_LOG"

# ============================================================
# [Step 1] Prerequisites
# ============================================================
log_section "Prerequisites"

# apt update: 필요한 패키지 중 하나라도 없으면 실행
_need_apt=0
for _cmd in curl git wget unzip gcc make rg fdfind clangd; do
    command -v "$_cmd" &>/dev/null || { _need_apt=1; break; }
done
if [ "$_need_apt" = "1" ]; then
    log_install "apt update"
    _t=$SECONDS
    $SUDO apt update -qq >> "$SETUP_LOG" 2>&1
    log_done "apt update ($(_elapsed $_t))"
else
    log_skip "apt update (all deps present)"
fi

# system packages (nvim 의존성 포함)
ensure_pkg curl
ensure_pkg git
ensure_pkg wget
ensure_pkg unzip
ensure_pkg gcc
ensure_pkg make
ensure_pkg ripgrep rg
ensure_pkg fd-find fdfind
ensure_pkg clangd

# node / gh
ensure_cmd node 22 install_node
ensure_cmd gh   2  install_gh

# npm LSP tools (node 설치 후)
if command -v npm &>/dev/null; then
    ensure_npm bash-language-server
fi

# ============================================================
# [Step 2] Claude Code
# ============================================================
log_section "Claude Code"

CLAUDE_CODE_VERSION="2.1.104"
CURRENT_CLAUDE_VER="$(claude --version 2>/dev/null || true)"
if [ "$CURRENT_CLAUDE_VER" = "$CLAUDE_CODE_VERSION (Claude Code)" ]; then
    log_skip "claude-code (v$CLAUDE_CODE_VERSION)"
else
    # native installer 바이너리가 있으면 제거 (npm 버전과 충돌 방지)
    rm -f "$HOME/.local/bin/claude" 2>/dev/null
    log_install "claude-code (v$CLAUDE_CODE_VERSION)"
    _t=$SECONDS
    # sudo는 nvm PATH를 상속하지 않으므로 env PATH를 명시적으로 전달
    $SUDO env PATH="$PATH" npm install -g "@anthropic-ai/claude-code@$CLAUDE_CODE_VERSION" >> "$SETUP_LOG" 2>&1 \
        || { log_fail "claude-code 설치 실패 (setup.log 참조)"; return 1; }
    hash -r
    log_done "claude-code ($(_elapsed $_t))"
fi

if command -v claude &>/dev/null; then
    _t=$SECONDS
    log_install "claude update"
    claude update --yes >> "$SETUP_LOG" 2>&1 || true
    hash -r
    log_done "claude update ($(_elapsed $_t))"
fi

# ============================================================
# [Step 3] Auth & Tokens
# ============================================================
log_section "Auth & Tokens"

TOKEN="$(cat "$SCRIPT_DIR/github_token.txt" 2>/dev/null | tr -d '[:space:]')"
if [ -z "$TOKEN" ]; then
    log_fail "github_token.txt is empty. Please fill in your GitHub token."
    return 1
fi
export GITHUB_TOKEN="$TOKEN"
log_pass "GITHUB_TOKEN set"

CLAUDE_TOKEN="$(cat "$SCRIPT_DIR/claude_token.txt" 2>/dev/null | tr -d '[:space:]')"
if [ -n "$CLAUDE_TOKEN" ]; then
    export CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_TOKEN"
    log_pass "CLAUDE_CODE_OAUTH_TOKEN set (${CLAUDE_CODE_OAUTH_TOKEN:0:12}...)"

    if command -v claude &>/dev/null; then
        AUTH_JSON="$(claude auth status 2>/dev/null)"
        if echo "$AUTH_JSON" | grep -q '"loggedIn": true'; then
            AUTH_METHOD="$(echo "$AUTH_JSON" | grep -oP '"authMethod": "\K[^"]*')"
            log_pass "Claude Code auth OK (method: ${AUTH_METHOD})"
        else
            log_fail "Claude Code auth FAILED"
        fi
    fi
else
    log_warn "claude_token.txt not found or empty"
fi

# ============================================================
# [Step 4] Git Config
# ============================================================
log_section "Git Config"

_t=$SECONDS
git config --global user.name "jhkim-XCENA"
git config --global user.email "jeongho.kim@xcena.com"
git config --global credential.helper \
    '!f() { echo username=x-access-token; echo password=$GITHUB_TOKEN; }; f'

# 각 레포에 local config 설정
for repo_dir in /sdk_release /sdk_release/tools/pxcc /llvm-project /microbenchmark; do
    if [ -d "$repo_dir/.git" ] || [ -f "$repo_dir/.git" ]; then
        git -C "$repo_dir" config user.name "jhkim-XCENA"
        git -C "$repo_dir" config user.email "jeongho.kim@xcena.com"
    fi
done
log_done "git config ($(_elapsed $_t))"

# ============================================================
# [Step 5] pxcc
# ============================================================
log_section "pxcc"

PXCC_DIR="/sdk_release/tools/pxcc"
if [ -d "$PXCC_DIR/.git" ] || [ -f "$PXCC_DIR/.git" ]; then
    _t=$SECONDS
    log_install "pxcc update (git pull)"
    git -C "$PXCC_DIR" pull --ff-only >> "$SETUP_LOG" 2>&1 \
        && log_done "pxcc update ($(_elapsed $_t))" \
        || log_warn "pxcc update 실패 (setup.log 참조)"

    if [ -f "$PXCC_DIR/scripts/install_dependencies.sh" ]; then
        _t=$SECONDS
        log_install "pxcc install_dependencies"
        bash "$PXCC_DIR/scripts/install_dependencies.sh" >> "$SETUP_LOG" 2>&1 \
            && log_done "pxcc install_dependencies ($(_elapsed $_t))" \
            || log_warn "pxcc install_dependencies 실패 (setup.log 참조)"
    else
        log_warn "pxcc/scripts/install_dependencies.sh 를 찾을 수 없음"
    fi
else
    log_skip "pxcc ($PXCC_DIR 없음)"
fi

# ============================================================
# [Step 6] Neovim
# ============================================================
log_section "Neovim"

_t=$SECONDS
cd "$SCRIPT_DIR/nvim" || return 1
TOTAL_START="$TOTAL_START" bash ./install.sh "$SETUP_LOG"
cd "$SCRIPT_DIR"
log_done "nvim setup ($(_elapsed $_t))"

# ============================================================
# [Step 7] Shell (.bashrc)
# ============================================================
log_section "Shell (.bashrc)"

BASHRC_FILE="$HOME/.bashrc"
if [ ! -f "$BASHRC_FILE" ]; then
    log_fail "$BASHRC_FILE is not found."
    return 1
fi

_t=$SECONDS
cp "$BASHRC_FILE" "${BASHRC_FILE}.bak_$(date +%Y%m%d%H%M%S)"

# PS1과 관련된 빈 if-else 구조를 제거합니다 (color_prompt 관련)
sed -i '/^if \[ "\$color_prompt" = yes \]; then$/,/^fi$/{ /^if \[ "\$color_prompt" = yes \]; then$/d; /^else$/d; /^fi$/d; }' "$BASHRC_FILE"

# --- jhkim-config 섹션 관리 ---
if grep -q "### jhkim-config start" "$BASHRC_FILE"; then
    sed -i '/### jhkim-config start/,/### jhkim-config end/d' "$BASHRC_FILE"
fi

echo "" >> "$BASHRC_FILE"
echo "### jhkim-config start" >> "$BASHRC_FILE"
cat >> "$BASHRC_FILE" << 'PROMPT_EOF'
__git_branch() {
  local b
  b="$(git symbolic-ref --short HEAD 2>/dev/null)" && echo " ($b)"
}
if [ -f /.dockerenv ]; then
  export PS1="\[\033[38;5;135m\][\A] \W\$(__git_branch)\$\[\033[0m\] "
else
  export PS1="\[\033[38;5;33m\][\A] \W\$(__git_branch)\$\[\033[0m\] "
fi
PROMPT_EOF
# nvm 로드 (db-devenv 이미지: /opt/nvm에 node/claude 설치됨)
cat >> "$BASHRC_FILE" << 'NVM_EOF'
if [ -s "${NVM_DIR:-/opt/nvm}/nvm.sh" ]; then
  export NVM_DIR="${NVM_DIR:-/opt/nvm}"
  . "$NVM_DIR/nvm.sh"
fi
NVM_EOF
echo "export GH_TOKEN=\"$TOKEN\"" >> "$BASHRC_FILE"
echo "export GITHUB_TOKEN=\"$TOKEN\"" >> "$BASHRC_FILE"
if [ -n "$CLAUDE_TOKEN" ]; then
    echo "export CLAUDE_CODE_OAUTH_TOKEN=\"$CLAUDE_TOKEN\"" >> "$BASHRC_FILE"
fi
echo "bind 'set enable-bracketed-paste off' 2>/dev/null" >> "$BASHRC_FILE"
echo "alias claude='claude --dangerously-skip-permissions'" >> "$BASHRC_FILE"
echo "### jhkim-config end" >> "$BASHRC_FILE"
log_done ".bashrc ($(_elapsed $_t))"

source ~/.bashrc
log_done "Setup complete (total: $(_elapsed $TOTAL_START))"
