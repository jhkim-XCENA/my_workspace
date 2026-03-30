#!/bin/bash

# 현재 스크립트를 source ./execute_with_source.sh 형태로 실행했는지 검사
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "this script should be executed like: source ./execute_with_source.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SUDO=""
if [[ $EUID -ne 0 ]]; then
    SUDO="sudo"
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Install helpers ---

# ensure_cmd <command> <min_major_version> <install_function>
# 명령어가 없거나 버전이 낮으면 install_function 실행
ensure_cmd() {
    local cmd="$1" min_ver="$2" install_fn="$3"
    if command -v "$cmd" &> /dev/null; then
        local cur_ver
        cur_ver="$("$cmd" --version 2>/dev/null | grep -oP '[0-9]+' | head -1)"
        if [ -n "$cur_ver" ] && [ "$cur_ver" -ge "$min_ver" ] 2>/dev/null; then
            echo -e "${GREEN}[skip]${NC} $cmd (v$cur_ver >= v$min_ver)"
            return 0
        fi
    fi
    echo -e "${YELLOW}[install]${NC} $cmd (requires v$min_ver+)"
    "$install_fn"
}

# ensure_pkg <package_name> [command_name]
# apt 패키지가 설치돼 있으면 건너뜀
ensure_pkg() {
    local pkg="$1" cmd="${2:-$1}"
    if command -v "$cmd" &> /dev/null; then
        echo -e "${GREEN}[skip]${NC} $pkg (already installed)"
        return 0
    fi
    if dpkg -s "$pkg" &> /dev/null; then
        echo -e "${GREEN}[skip]${NC} $pkg (already installed)"
        return 0
    fi
    echo -e "${YELLOW}[install]${NC} $pkg"
    $SUDO apt install -y "$pkg"
}

# ensure_npm <package_name>
ensure_npm() {
    local pkg="$1"
    if npm list -g "$pkg" &> /dev/null; then
        echo -e "${GREEN}[skip]${NC} npm:$pkg (already installed)"
        return 0
    fi
    echo -e "${YELLOW}[install]${NC} npm:$pkg"
    npm install -g "$pkg"
}

# ensure_file <path> <install_function>
ensure_file() {
    local path="$1" install_fn="$2"
    if [ -f "$path" ]; then
        echo -e "${GREEN}[skip]${NC} $path (already exists)"
        return 0
    fi
    echo -e "${YELLOW}[install]${NC} creating $path"
    "$install_fn"
}

# --- Install: Node.js v22+ ---
install_node() {
    curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO -E bash -
    $SUDO apt install -y nodejs
}

# --- Install: glow (Charm repo) ---
install_glow() {
    $SUDO mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | $SUDO gpg --batch --yes --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | $SUDO tee /etc/apt/sources.list.d/charm.list > /dev/null
    $SUDO apt update -qq
    $SUDO apt install -y glow
}

# --- Main ---
echo "=== Environment Setup ==="

$SUDO apt update -qq

ensure_cmd node 22 install_node
ensure_pkg glow glow || install_glow

echo ""
echo "Script directory: $SCRIPT_DIR"

# GitHub token 설정
TOKEN="$(cat "$SCRIPT_DIR/token.txt" 2>/dev/null | tr -d '[:space:]')"
if [ -z "$TOKEN" ]; then
    echo "Error: token.txt is empty. Please fill in your GitHub token into $SCRIPT_DIR/token.txt"
    return 1
fi
export GITHUB_TOKEN="$TOKEN"
echo "GITHUB_TOKEN set from token.txt"

# nvim 설치
cd "$SCRIPT_DIR/nvim" || return 1
bash ./install.sh
cd "$SCRIPT_DIR"

# --- .bashrc 설정 ---
BASHRC_FILE="$HOME/.bashrc"

if [ ! -f "$BASHRC_FILE" ]; then
    echo "error: $BASHRC_FILE is not found."
    return 1
fi

echo "--- update $BASHRC_FILE ---"

cp "$BASHRC_FILE" "${BASHRC_FILE}.bak_ps1_$(date +%Y%m%d%H%M%S)"
echo "backup: ${BASHRC_FILE}.bak_ps1_..."

# PS1과 관련된 빈 if-else 구조를 제거합니다 (color_prompt 관련)
sed -i '/^if \[ "\$color_prompt" = yes \]; then$/,/^fi$/{ /^if \[ "\$color_prompt" = yes \]; then$/d; /^else$/d; /^fi$/d; }' "$BASHRC_FILE"

# --- jhkim-config 섹션 관리 ---
if grep -q "### jhkim-config start" "$BASHRC_FILE"; then
    echo "Removing existing jhkim-config section..."
    sed -i '/### jhkim-config start/,/### jhkim-config end/d' "$BASHRC_FILE"
fi

echo "" >> "$BASHRC_FILE"
echo "### jhkim-config start" >> "$BASHRC_FILE"
echo 'export PS1="\[\033[38;5;135m\][\A] \W\$\[\033[0m\] "' >> "$BASHRC_FILE"
echo "alias claude='claude --dangerously-skip-permissions'" >> "$BASHRC_FILE"
echo "### jhkim-config end" >> "$BASHRC_FILE"

echo ""
source ~/.bashrc
echo "Setup complete! Run:"
echo "  source ~/.bashrc"
