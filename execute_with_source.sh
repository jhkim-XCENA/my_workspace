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
    "$install_fn" >> "$SETUP_LOG" 2>&1
}

# ensure_pkg <package_name> [command_name]
ensure_pkg() {
    local pkg="$1" cmd="${2:-$1}"
    if command -v "$cmd" &> /dev/null || dpkg -s "$pkg" &> /dev/null; then
        log "${GREEN}[skip]${NC} $pkg"
        return 0
    fi
    log "${YELLOW}[install]${NC} $pkg"
    $SUDO apt install -y "$pkg" >> "$SETUP_LOG" 2>&1
}

# ensure_npm <package_name>
ensure_npm() {
    local pkg="$1"
    if npm list -g "$pkg" &> /dev/null; then
        log "${GREEN}[skip]${NC} npm:$pkg"
        return 0
    fi
    log "${YELLOW}[install]${NC} npm:$pkg"
    npm install -g "$pkg" >> "$SETUP_LOG" 2>&1
}

# --- Install functions ---

install_node() {
    curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO -E bash -
    $SUDO apt install -y nodejs
}

install_glow() {
    $SUDO mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | $SUDO gpg --batch --yes --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | $SUDO tee /etc/apt/sources.list.d/charm.list > /dev/null
    $SUDO apt update -qq
    $SUDO apt install -y glow
}

install_gh() {
    $SUDO mkdir -p /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | $SUDO tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | $SUDO tee /etc/apt/sources.list.d/github-cli-stable.list > /dev/null
    $SUDO apt update -qq
    $SUDO apt install -y gh
}

# --- Main ---
log "=== Environment Setup (detail: $SETUP_LOG) ==="

log "Updating apt..."
$SUDO apt update -qq >> "$SETUP_LOG" 2>&1

ensure_pkg curl
ensure_cmd node 22 install_node
ensure_cmd glow 0 install_glow
ensure_cmd gh 2 install_gh

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

    # ~/.claude.json에 저장된 oauthAccount 제거
    # (저장된 만료 세션이 CLAUDE_CODE_OAUTH_TOKEN보다 우선되어 브라우저 인증을 유발하는 문제 방지)
    if [ -f "$HOME/.claude.json" ]; then
        python3 -c "
import json, sys
path = '$HOME/.claude.json'
with open(path) as f:
    d = json.load(f)
if 'oauthAccount' in d:
    del d['oauthAccount']
    with open(path, 'w') as f:
        json.dump(d, f)
    print('oauthAccount cleared from ~/.claude.json')
" && log "oauthAccount cleared from ~/.claude.json (CLAUDE_CODE_OAUTH_TOKEN 우선 사용)"
    fi
else
    log "${YELLOW}Warning:${NC} claude_token.txt not found or empty. Claude Code OAuth token not set."
fi

# nvim 설치
log "Running nvim setup..."
cd "$SCRIPT_DIR/nvim" || return 1
bash ./install.sh "$SETUP_LOG"
cd "$SCRIPT_DIR"

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
echo "alias claude='claude --dangerously-skip-permissions'" >> "$BASHRC_FILE"
echo "### jhkim-config end" >> "$BASHRC_FILE"

log ""
source ~/.bashrc
log "${GREEN}Setup complete!${NC}"
