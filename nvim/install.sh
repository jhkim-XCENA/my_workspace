#!/bin/bash

# Color Variables
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Starting Neovim v0.11+ Environment Setup ===${NC}"

# 0. Check if we need sudo
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi

# 1. Dependency Check
# Neovim 플러그인 구동에 필요한 필수 패키지들 (GCC는 Treesitter 컴파일용, Ripgrep은 검색용)
REQUIRED_PACKAGES="git curl wget unzip gcc make ripgrep fd-find"

# clangd 확인 (C++ 개발용)
if ! command -v clangd &> /dev/null; then
    REQUIRED_PACKAGES+=" clangd"
fi

# Node.js 확인 (Copilot 구동에 필수 - v22 이상 필요)
NODE_VERSION=""
if command -v node &> /dev/null; then
    NODE_VERSION=$(node -v | grep -oP 'v\K[0-9]+')
fi

if [ -z "$NODE_VERSION" ] || [ "$NODE_VERSION" -lt 22 ]; then
    echo -e "${YELLOW}Node.js v22+ required for Copilot. Installing Node.js v22.x...${NC}"
    if [ -n "$SUDO" ]; then
        curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO -E bash -
    else
        curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    fi
    REQUIRED_PACKAGES+=" nodejs"
fi

npm install -g bash-language-server

echo -e "${YELLOW}Checking dependencies...${NC}"
if $SUDO apt update && $SUDO apt install -y $REQUIRED_PACKAGES; then
    echo -e "${GREEN}Dependencies installed successfully!${NC}"
else
    echo -e "${RED}Failed to install dependencies.${NC}"
    exit 1
fi

# 2. Neovim Version Check (Binary Install if missing or old)
INSTALL_NVIM=false
if ! command -v nvim &> /dev/null; then
    INSTALL_NVIM=true
else
    # 버전 체크 (v0.9 미만이면 재설치 유도)
    CURRENT_VER=$(nvim --version | head -n1 | grep -oP 'v\K[0-9]+\.[0-9]+')
    if [[ "$CURRENT_VER" < "0.9" ]]; then
        echo -e "${YELLOW}Detected old Neovim version ($CURRENT_VER). Re-installing latest...${NC}"
        INSTALL_NVIM=true
    fi
fi

if [ "$INSTALL_NVIM" = true ]; then
    echo -e "${BLUE}Installing latest Neovim stable binary...${NC}"
    # 기존 삭제
    $SUDO rm -f /usr/local/bin/nvim
    $SUDO rm -rf /opt/nvim
    
    # 다운로드 및 설치 (x86_64)
    curl -LO https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz
    $SUDO tar -C /opt -xzf nvim-linux-x86_64.tar.gz
    $SUDO ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
    rm nvim-linux-x86_64.tar.gz
    echo -e "${GREEN}Neovim installed!${NC}"
fi

# 3. Clean up old Packer (if exists) to prevent conflicts
PACKER_DIR="$HOME/.local/share/nvim/site/pack/packer"
if [ -d "$PACKER_DIR" ]; then
    echo -e "${YELLOW}Removing old Packer artifacts...${NC}"
    rm -rf "$PACKER_DIR"
fi

# 4. Config Linking
CONFIG_DIR="$HOME/.config/nvim"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

if [ -d "$CONFIG_DIR" ] && [ ! -L "$CONFIG_DIR" ]; then
    echo "Backing up existing config..."
    mv "$CONFIG_DIR" "${CONFIG_DIR}.backup_$(date +%Y%m%d_%H%M%S)"
fi

echo "Linking configuration..."
mkdir -p "$HOME/.config"
ln -sf "$SCRIPT_DIR" "$CONFIG_DIR"

# 5. Setup Aliases (vi, vim -> nvim)
echo -e "${BLUE}Configuring shell aliases (vi/vim -> nvim)...${NC}"

add_aliases() {
    local RC_FILE="$1"
    local SHELL_NAME="$2"

    if [ -f "$RC_FILE" ]; then
        # 중복 추가 방지
        if grep -q "alias vi='nvim'" "$RC_FILE"; then
            echo -e "${YELLOW}Aliases already exist in $SHELL_NAME config.${NC}"
        else
            echo "" >> "$RC_FILE"
            echo "# --- Added by nvim-config install script ---" >> "$RC_FILE"
            echo "export EDITOR='nvim'" >> "$RC_FILE"
            echo "alias vi='nvim'" >> "$RC_FILE"
            echo "alias vim='nvim'" >> "$RC_FILE"
            echo "alias view='nvim -R'" >> "$RC_FILE"
            echo "# -------------------------------------------" >> "$RC_FILE"
            echo -e "${GREEN}Added aliases to $SHELL_NAME config ($RC_FILE)${NC}"
        fi
    fi
}

# Bash와 Zsh 설정 파일에 적용
add_aliases "$HOME/.bashrc" "Bash"
add_aliases "$HOME/.zshrc" "Zsh"

echo -e "${GREEN}=== Setup Complete! ===${NC}"
echo -e "To apply the changes immediately, run:\n"
echo -e "    ${YELLOW}source ~/.bashrc${NC}\n"
echo "Then try typing 'vi' or 'vim'."

echo -e "${GREEN}=== Setup Complete! ===${NC}"
echo "Run 'nvim' and wait for Lazy.nvim to install plugins."
