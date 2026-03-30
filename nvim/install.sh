#!/bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Starting Neovim v0.11+ Environment Setup ===${NC}"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi

# --- Install helpers ---

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

ensure_npm() {
    local pkg="$1"
    if npm list -g "$pkg" &> /dev/null; then
        echo -e "${GREEN}[skip]${NC} npm:$pkg (already installed)"
        return 0
    fi
    echo -e "${YELLOW}[install]${NC} npm:$pkg"
    npm install -g "$pkg"
}

# --- Install functions ---

install_node() {
    if [ -n "$SUDO" ]; then
        curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO -E bash -
    else
        curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    fi
    $SUDO apt install -y nodejs
}

install_nvim() {
    echo -e "${BLUE}Installing latest Neovim stable binary...${NC}"
    $SUDO rm -f /usr/local/bin/nvim
    $SUDO rm -rf /opt/nvim /opt/nvim-linux-x86_64

    curl -LO https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz
    $SUDO tar -C /opt -xzf nvim-linux-x86_64.tar.gz
    $SUDO ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
    rm nvim-linux-x86_64.tar.gz
    echo -e "${GREEN}Neovim installed!${NC}"
}

# --- 1. Dependencies ---
echo -e "${YELLOW}Checking dependencies...${NC}"
$SUDO apt update -qq

ensure_cmd node 22 install_node
ensure_pkg git
ensure_pkg curl
ensure_pkg wget
ensure_pkg unzip
ensure_pkg gcc
ensure_pkg make
ensure_pkg ripgrep rg
ensure_pkg fd-find fdfind
ensure_pkg clangd
ensure_npm bash-language-server

# --- 2. Neovim (v0.9+) ---
ensure_cmd nvim 0 install_nvim
# 추가 버전 체크: 0.9 미만이면 재설치
if command -v nvim &> /dev/null; then
    CURRENT_VER=$(nvim --version | head -n1 | grep -oP 'v\K[0-9]+\.[0-9]+')
    if awk -v ver="$CURRENT_VER" 'BEGIN {exit !(ver < 0.9)}'; then
        echo -e "${YELLOW}Detected old Neovim version ($CURRENT_VER). Re-installing...${NC}"
        install_nvim
    else
        echo -e "${GREEN}[skip]${NC} nvim (v$CURRENT_VER >= v0.9)"
    fi
fi

# --- 3. Clean up old Packer ---
PACKER_DIR="$HOME/.local/share/nvim/site/pack/packer"
if [ -d "$PACKER_DIR" ]; then
    echo -e "${YELLOW}Removing old Packer artifacts...${NC}"
    rm -rf "$PACKER_DIR"
fi

# --- 4. Config Linking ---
CONFIG_DIR="$HOME/.config/nvim"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

if [ -L "$CONFIG_DIR" ] && [ "$(readlink -f "$CONFIG_DIR")" = "$(readlink -f "$SCRIPT_DIR")" ]; then
    echo -e "${GREEN}[skip]${NC} nvim config symlink (already correct)"
else
    if [ -d "$CONFIG_DIR" ] && [ ! -L "$CONFIG_DIR" ]; then
        echo "Backing up existing config..."
        mv "$CONFIG_DIR" "${CONFIG_DIR}.backup_$(date +%Y%m%d_%H%M%S)"
    fi
    echo "Linking configuration..."
    mkdir -p "$HOME/.config"
    ln -sf "$SCRIPT_DIR" "$CONFIG_DIR"
fi

# --- 5. Shell Aliases ---
add_aliases() {
    local RC_FILE="$1" SHELL_NAME="$2"
    if [ -f "$RC_FILE" ]; then
        if grep -q "alias vi='nvim'" "$RC_FILE"; then
            echo -e "${GREEN}[skip]${NC} $SHELL_NAME aliases (already exist)"
        else
            echo "" >> "$RC_FILE"
            echo "# --- Added by nvim-config install script ---" >> "$RC_FILE"
            echo "export EDITOR='nvim'" >> "$RC_FILE"
            echo "alias vi='nvim'" >> "$RC_FILE"
            echo "alias vim='nvim'" >> "$RC_FILE"
            echo "alias view='nvim -R'" >> "$RC_FILE"
            echo "alias c='clear'" >> "$RC_FILE"
            echo "# -------------------------------------------" >> "$RC_FILE"
            echo -e "${GREEN}Added aliases to $SHELL_NAME config${NC}"
        fi
    fi
}

add_aliases "$HOME/.bashrc" "Bash"
add_aliases "$HOME/.zshrc" "Zsh"

echo -e "${GREEN}=== Setup Complete! ===${NC}"
echo "Run 'nvim' and wait for Lazy.nvim to install plugins."
