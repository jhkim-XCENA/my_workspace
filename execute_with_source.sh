#!/bin/bash

# 현재 스크립트를 source ./setup.sh 형태로 실행했는지 검사
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "this script should be executed like: source ./setup.sh"
    exit 1
fi

SUDO=""
if [[ $EUID -ne 0 ]]; then
    SUDO="sudo"
fi

# npm 설치
$SUDO apt update
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# 즉시 사용을 위해 환경변수 직접 로드 (bashrc 대신)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

nvm install --lts
# copilot cli 설치
npm install -g @github/copilot

# install glow
mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | tee /etc/apt/sources.list.d/charm.list
apt update && apt install glow


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Script directory: $SCRIPT_DIR"

# GitHub token 설정
TOKEN="$(cat "$SCRIPT_DIR/token.txt" 2>/dev/null || true)"
if [ -n "$TOKEN" ]; then
    export GITHUB_TOKEN="$TOKEN"
    echo "GITHUB_TOKEN set from token.txt"
else
    echo "Warning: token.txt not found, GITHUB_TOKEN not set"
fi

# cd는 현재 셸에서 실행되어야 하므로 sudo 없이 실행
cd "$SCRIPT_DIR/nvim" || exit 1
bash ./install.sh
cd ..

BASHRC_FILE="$HOME/.bashrc"

if [ ! -f "$BASHRC_FILE" ]; then
    echo "error: $BASHRC_FILE is not found."
    exit 1
fi

echo "--- update $BASHRC_FILE ---"

# 기존 파일을 백업합니다.
cp "$BASHRC_FILE" "${BASHRC_FILE}.bak_ps1_$(date +%Y%m%d%H%M%S)"
echo "backup: ${BASHRC_FILE}.bak_ps1_..."

# PS1과 관련된 빈 if-else 구조를 제거합니다 (color_prompt 관련)
sed -i '/^if \[ "\$color_prompt" = yes \]; then$/,/^fi$/{ /^if \[ "\$color_prompt" = yes \]; then$/d; /^else$/d; /^fi$/d; }' "$BASHRC_FILE"

# --- jhkim-config 섹션 관리 ---
# 기존 jhkim-config ps1 섹션이 있으면 제거
if grep -q "### jhkim-config ps1 start" "$BASHRC_FILE"; then
    echo "Removing existing jhkim-config ps1 section..."
    sed -i '/### jhkim-config ps1 start/,/### jhkim-config ps1 end/d' "$BASHRC_FILE"
fi

# 새로운 PS1 설정 추가 (보라색 컬러)
# \033[38;5;135m: 보라색 (256 컬러 모드)
# \033[0m: 컬러 리셋
# \A: 시간 (HH:MM)
# \W: 현재 작업 디렉토리의 마지막 구성 요소
echo "" >> "$BASHRC_FILE"
echo "### jhkim-config ps1 start" >> "$BASHRC_FILE"
echo 'export PS1="\[\033[38;5;135m\][\A] \W\$\[\033[0m\] "' >> "$BASHRC_FILE"
echo "### jhkim-config ps1 end" >> "$BASHRC_FILE"

echo ""
source ~/.bashrc
echo "Setup complete! Run:"
echo "  source ~/.bashrc"
