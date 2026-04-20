#!/bin/bash
# nvim 바이너리 설치 + config 심링크 + alias 설정
# apt/npm 패키지는 execute_with_source.sh에서 설치됨

SETUP_LOG="${1:-/dev/null}"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
GRAY='\033[0;90m'
NC='\033[0m'

# TOTAL_START는 execute_with_source.sh에서 env로 전달됨
TOTAL_START="${TOTAL_START:-$SECONDS}"
_ts()      { printf "${GRAY}[%02d:%02d]${NC}" $(( (SECONDS - TOTAL_START) / 60 )) $(( (SECONDS - TOTAL_START) % 60 )); }
_elapsed() { local d=$((SECONDS - $1)); printf "%dm %ds" $((d/60)) $((d%60)); }

log_done()    { echo -e "$(_ts)${GREEN}[done]${NC} $1"; }
log_skip()    { echo -e "$(_ts)${GREEN}[skip]${NC} $1"; }
log_install() { echo -e "$(_ts)${YELLOW}[install]${NC} $1"; }

install_nvim() {
    $SUDO rm -f /usr/local/bin/nvim
    $SUDO rm -rf /opt/nvim /opt/nvim-linux-x86_64
    curl -LO https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz
    $SUDO tar -C /opt -xzf nvim-linux-x86_64.tar.gz
    $SUDO ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
    rm -f nvim-linux-x86_64.tar.gz
}

version_ge() { printf '%s\n%s\n' "$2" "$1" | sort -V -C; }

# --- 1. Neovim binary (>= 0.9) ---
NVIM_MIN="0.9"
if command -v nvim &> /dev/null; then
    CURRENT_VER=$(nvim --version | head -n1 | grep -oP 'v\K[0-9]+\.[0-9]+')
    if version_ge "$CURRENT_VER" "$NVIM_MIN"; then
        log_skip "nvim (v$CURRENT_VER)"
    else
        log_install "nvim (v$CURRENT_VER < v$NVIM_MIN)"
        _t=$SECONDS
        install_nvim >> "$SETUP_LOG" 2>&1
        log_done "nvim ($(_elapsed $_t))"
    fi
else
    log_install "nvim"
    _t=$SECONDS
    install_nvim >> "$SETUP_LOG" 2>&1
    log_done "nvim ($(_elapsed $_t))"
fi

# --- 2. Clean up old Packer ---
PACKER_DIR="$HOME/.local/share/nvim/site/pack/packer"
if [ -d "$PACKER_DIR" ]; then
    log_install "removing old Packer artifacts"
    rm -rf "$PACKER_DIR"
fi

# --- 3. Config symlink ---
CONFIG_DIR="$HOME/.config/nvim"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

if [ -L "$CONFIG_DIR" ] && [ "$(readlink -f "$CONFIG_DIR")" = "$(readlink -f "$SCRIPT_DIR")" ]; then
    log_skip "nvim config symlink"
else
    if [ -d "$CONFIG_DIR" ] && [ ! -L "$CONFIG_DIR" ]; then
        mv "$CONFIG_DIR" "${CONFIG_DIR}.backup_$(date +%Y%m%d_%H%M%S)"
    fi
    log_install "nvim config symlink"
    mkdir -p "$HOME/.config"
    ln -sf "$SCRIPT_DIR" "$CONFIG_DIR"
    log_done "nvim config symlink"
fi

# --- 4. Shell aliases ---
_add_aliases() {
    local RC_FILE="$1" SHELL_NAME="$2"
    if [ -f "$RC_FILE" ]; then
        if grep -q "alias vi='nvim'" "$RC_FILE"; then
            log_skip "$SHELL_NAME aliases"
        else
            echo "" >> "$RC_FILE"
            echo "# --- Added by nvim-config install script ---" >> "$RC_FILE"
            echo "export EDITOR='nvim'" >> "$RC_FILE"
            echo "alias vi='nvim'" >> "$RC_FILE"
            echo "alias vim='nvim'" >> "$RC_FILE"
            echo "alias view='nvim -R'" >> "$RC_FILE"
            echo "alias c='clear'" >> "$RC_FILE"
            echo "# -------------------------------------------" >> "$RC_FILE"
            log_done "$SHELL_NAME aliases"
        fi
    fi
}

_add_aliases "$HOME/.bashrc" "Bash"
_add_aliases "$HOME/.zshrc" "Zsh"
