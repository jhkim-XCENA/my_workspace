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

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "$@"; }
log_detail() { echo "$@" >> "$SETUP_LOG" 2>&1; }

# --- Timing helpers ---
TOTAL_START=$SECONDS
fmt_elapsed() {
    local dur=$((SECONDS - $1))
    local mins=$((dur / 60))
    local secs=$((dur % 60))
    printf "%dm %ds" "$mins" "$secs"
}

# --- Install helpers ---

# ensure_cmd <command> <min_major_version> <install_function>
ensure_cmd() {
    local cmd="$1" min_ver="$2" install_fn="$3"
    if command -v "$cmd" &> /dev/null; then
        local cur_ver
        cur_ver="$("$cmd" --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+' | head -1)"
        local cur_major="${cur_ver%%.*}"
        if [ -n "$cur_major" ] && [ "$cur_major" -ge "$min_ver" ] 2>/dev/null; then
            log "${GREEN}[skip]${NC} $cmd (v$cur_ver >= v$min_ver)"
            return 0
        fi
    fi
    log "${YELLOW}[install]${NC} $cmd (requires v$min_ver+)"
    local _t=$SECONDS
    "$install_fn" >> "$SETUP_LOG" 2>&1
    log "  ${GREEN}[done]${NC} $cmd ($(fmt_elapsed $_t))"
}

# ensure_pkg <package_name> [command_name]
ensure_pkg() {
    local pkg="$1" cmd="${2:-$1}"
    if command -v "$cmd" &> /dev/null || dpkg -s "$pkg" &> /dev/null; then
        log "${GREEN}[skip]${NC} $pkg"
        return 0
    fi
    log "${YELLOW}[install]${NC} $pkg"
    local _t=$SECONDS
    $SUDO apt install -y "$pkg" >> "$SETUP_LOG" 2>&1
    log "  ${GREEN}[done]${NC} $pkg ($(fmt_elapsed $_t))"
}

# ensure_npm <package_name>
ensure_npm() {
    local pkg="$1"
    if npm list -g "$pkg" &> /dev/null; then
        log "${GREEN}[skip]${NC} npm:$pkg"
        return 0
    fi
    log "${YELLOW}[install]${NC} npm:$pkg"
    local _t=$SECONDS
    npm install -g "$pkg" >> "$SETUP_LOG" 2>&1
    log "  ${GREEN}[done]${NC} npm:$pkg ($(fmt_elapsed $_t))"
}

# --- Install functions ---

install_node() {
    bash "$SCRIPT_DIR/third_party/install_node.sh"
}

install_gh() {
    bash "$SCRIPT_DIR/third_party/install_gh.sh"
}

# --- Main ---
log "=== Environment Setup (detail: $SETUP_LOG) ==="

log "Updating apt..."
_t=$SECONDS
$SUDO apt update -qq >> "$SETUP_LOG" 2>&1
log "  ${GREEN}[done]${NC} apt update ($(fmt_elapsed $_t))"

ensure_pkg curl
ensure_cmd node 22 install_node
ensure_cmd gh 2 install_gh

# Claude Code 설치 (npm으로 버전 고정)
CLAUDE_CODE_VERSION="2.1.104"
CURRENT_CLAUDE_VER="$(claude --version 2>/dev/null || true)"
if [ "$CURRENT_CLAUDE_VER" = "$CLAUDE_CODE_VERSION (Claude Code)" ]; then
    log "${GREEN}[skip]${NC} claude-code (v$CLAUDE_CODE_VERSION)"
else
    # native installer 바이너리가 있으면 제거 (npm 버전과 충돌 방지)
    rm -f "$HOME/.local/bin/claude" 2>/dev/null
    log "${YELLOW}[install]${NC} claude-code (v$CLAUDE_CODE_VERSION)"
    _t=$SECONDS
    $SUDO npm install -g "@anthropic-ai/claude-code@$CLAUDE_CODE_VERSION" >> "$SETUP_LOG" 2>&1
    hash -r
    log "  ${GREEN}[done]${NC} claude-code ($(fmt_elapsed $_t))"
fi

log ""
log "Script directory: $SCRIPT_DIR"

# GitHub token 설정
TOKEN="$(cat "$SCRIPT_DIR/github_token.txt" 2>/dev/null | tr -d '[:space:]')"
if [ -z "$TOKEN" ]; then
    log "${RED}Error:${NC} github_token.txt is empty. Please fill in your GitHub token into $SCRIPT_DIR/github_token.txt"
    return 1
fi
export GITHUB_TOKEN="$TOKEN"
log "GITHUB_TOKEN set from github_token.txt"

# Claude OAuth token 설정
CLAUDE_TOKEN="$(cat "$SCRIPT_DIR/claude_token.txt" 2>/dev/null | tr -d '[:space:]')"
if [ -n "$CLAUDE_TOKEN" ]; then
    export CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_TOKEN"
    log "CLAUDE_CODE_OAUTH_TOKEN set from claude_token.txt"

    # 환경변수 전달 검증 (토큰 앞 12자만 표시)
    TOKEN_PREVIEW="${CLAUDE_CODE_OAUTH_TOKEN:0:12}..."
    log "  → CLAUDE_CODE_OAUTH_TOKEN = ${TOKEN_PREVIEW}"

    # Claude Code 설치 및 인증 검증
    if command -v claude &>/dev/null; then
        CLAUDE_VER="$(claude --version 2>/dev/null)"
        log "  → Claude Code installed: v${CLAUDE_VER}"

        AUTH_JSON="$(claude auth status 2>/dev/null)"
        if echo "$AUTH_JSON" | grep -q '"loggedIn": true'; then
            AUTH_METHOD="$(echo "$AUTH_JSON" | grep -oP '"authMethod": "\K[^"]*')"
            log "  ${GREEN}→ Claude Code auth OK${NC} (method: ${AUTH_METHOD})"
        else
            log "  ${RED}→ Claude Code auth FAILED${NC}"
            log "  ${YELLOW}  claude auth status 출력:${NC} $AUTH_JSON"
        fi
    else
        log "  ${YELLOW}→ Claude Code not installed yet (skipping auth check)${NC}"
    fi
else
    log "${YELLOW}Warning:${NC} claude_token.txt not found or empty. Claude Code OAuth token not set."
fi

# nvim 설치
log "Running nvim setup..."
_t=$SECONDS
cd "$SCRIPT_DIR/nvim" || return 1
bash ./install.sh "$SETUP_LOG"
cd "$SCRIPT_DIR"
log "  ${GREEN}[done]${NC} nvim setup ($(fmt_elapsed $_t))"

# --- .bashrc 설정 ---
BASHRC_FILE="$HOME/.bashrc"

if [ ! -f "$BASHRC_FILE" ]; then
    log "${RED}error:${NC} $BASHRC_FILE is not found."
    return 1
fi

log "Updating $BASHRC_FILE..."
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
echo "export GH_TOKEN=\"$TOKEN\"" >> "$BASHRC_FILE"
echo "bind 'set enable-bracketed-paste off' 2>/dev/null" >> "$BASHRC_FILE"
echo "alias claude='claude --dangerously-skip-permissions'" >> "$BASHRC_FILE"
echo "### jhkim-config end" >> "$BASHRC_FILE"

log ""
source ~/.bashrc
log "${GREEN}Setup complete!${NC} (total: $(fmt_elapsed $TOTAL_START))"
