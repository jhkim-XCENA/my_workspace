#!/bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# setup.log 경로: 인자로 받거나 기본값
SETUP_LOG="${1:-/dev/null}"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi

log() { echo -e "$@"; }
log_detail() { echo "$@" >> "$SETUP_LOG" 2>&1; }

# --- Install helpers ---

ensure_cmd() {
    local cmd="$1" min_ver="$2" install_fn="$3"
    if command -v "$cmd" &> /dev/null; then
        local cur_ver
        cur_ver="$("$cmd" --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+' | head -1)"
        local cur_major="${cur_ver%%.*}"
        if [ -n "$cur_major" ] && [ "$cur_major" -ge "$min_ver" ] 2>/dev/null; then
            log "${GREEN}[skip]${NC} $cmd (v$cur_ver)"
            return 0
        fi
    fi
    log "${YELLOW}[install]${NC} $cmd (requires v$min_ver+)"
    "$install_fn" >> "$SETUP_LOG" 2>&1
}

ensure_pkg() {
    local pkg="$1" cmd="${2:-$1}"
    if command -v "$cmd" &> /dev/null || dpkg -s "$pkg" &> /dev/null; then
        log "${GREEN}[skip]${NC} $pkg"
        return 0
    fi
    log "${YELLOW}[install]${NC} $pkg"
    $SUDO apt install -y "$pkg" >> "$SETUP_LOG" 2>&1
}

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

install_nvim() {
    $SUDO rm -f /usr/local/bin/nvim
    $SUDO rm -rf /opt/nvim /opt/nvim-linux-x86_64
    curl -LO https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz
    $SUDO tar -C /opt -xzf nvim-linux-x86_64.tar.gz
    $SUDO ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
    rm -f nvim-linux-x86_64.tar.gz
}

# version_ge <current> <required> : true if current >= required
# Compares dotted version strings correctly (e.g., 0.12 >= 0.9 → true)
version_ge() {
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

# --- Main ---
log "${BLUE}=== Neovim Environment Setup ===${NC}"

log "Updating apt..."
$SUDO apt update -qq >> "$SETUP_LOG" 2>&1

# 1. Dependencies
ensure_pkg curl
ensure_cmd node 22 install_node
ensure_pkg git
ensure_pkg wget
ensure_pkg unzip
ensure_pkg gcc
ensure_pkg make
ensure_pkg ripgrep rg
ensure_pkg fd-find fdfind
ensure_pkg clangd
if command -v npm &> /dev/null; then
    ensure_npm bash-language-server
fi

# 2. Neovim (>= 0.9)
NVIM_MIN="0.9"
if command -v nvim &> /dev/null; then
    CURRENT_VER=$(nvim --version | head -n1 | grep -oP 'v\K[0-9]+\.[0-9]+')
    if version_ge "$CURRENT_VER" "$NVIM_MIN"; then
        log "${GREEN}[skip]${NC} nvim (v$CURRENT_VER)"
    else
        log "${YELLOW}[install]${NC} nvim (v$CURRENT_VER < v$NVIM_MIN)"
        install_nvim >> "$SETUP_LOG" 2>&1
    fi
else
    log "${YELLOW}[install]${NC} nvim"
    install_nvim >> "$SETUP_LOG" 2>&1
fi

# 3. Clean up old Packer
PACKER_DIR="$HOME/.local/share/nvim/site/pack/packer"
if [ -d "$PACKER_DIR" ]; then
    log "${YELLOW}Removing old Packer artifacts...${NC}"
    rm -rf "$PACKER_DIR"
fi

# 4. Config Linking
CONFIG_DIR="$HOME/.config/nvim"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

if [ -L "$CONFIG_DIR" ] && [ "$(readlink -f "$CONFIG_DIR")" = "$(readlink -f "$SCRIPT_DIR")" ]; then
    log "${GREEN}[skip]${NC} nvim config symlink"
else
    if [ -d "$CONFIG_DIR" ] && [ ! -L "$CONFIG_DIR" ]; then
        mv "$CONFIG_DIR" "${CONFIG_DIR}.backup_$(date +%Y%m%d_%H%M%S)"
    fi
    log "Linking nvim config -> $SCRIPT_DIR"
    mkdir -p "$HOME/.config"
    ln -sf "$SCRIPT_DIR" "$CONFIG_DIR"
fi

# 5. Shell Aliases
add_aliases() {
    local RC_FILE="$1" SHELL_NAME="$2"
    if [ -f "$RC_FILE" ]; then
        if grep -q "alias vi='nvim'" "$RC_FILE"; then
            log "${GREEN}[skip]${NC} $SHELL_NAME aliases"
        else
            echo "" >> "$RC_FILE"
            echo "# --- Added by nvim-config install script ---" >> "$RC_FILE"
            echo "export EDITOR='nvim'" >> "$RC_FILE"
            echo "alias vi='nvim'" >> "$RC_FILE"
            echo "alias vim='nvim'" >> "$RC_FILE"
            echo "alias view='nvim -R'" >> "$RC_FILE"
            echo "alias c='clear'" >> "$RC_FILE"
            echo "# -------------------------------------------" >> "$RC_FILE"
            log "${GREEN}Added aliases to $SHELL_NAME${NC}"
        fi
    fi
}

add_aliases "$HOME/.bashrc" "Bash"
add_aliases "$HOME/.zshrc" "Zsh"

log "${GREEN}=== Neovim Setup Complete! ===${NC}"
