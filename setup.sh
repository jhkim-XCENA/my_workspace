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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
$SUDO echo $SCRIPT_DIR

$SUDO cd $SCRIPT_DIR
$SUDO cd nvim
$SUDO source ./install.sh
cd ..

BASHRC_FILE="$HOME/.bashrc"

if [ ! -f "$BASHRC_FILE" ]; then
    echo "error: $BASHRC_FILE is not found."
    exit 1
fi

echo "--- update $BASHRC_FILE ---"

# --- 2. 기존 PS1 설정 라인 삭제 (PS1=로 시작하는 모든 라인) ---
# 기존 파일을 백업합니다.
cp "$BASHRC_FILE" "${BASHRC_FILE}.bak_ps1_$(date +%Y%m%d%H%M%S)"
echo "backup: ${BASHRC_FILE}.bak_ps1_..."

# grep -v를 사용하여 'PS1=' 문자열을 포함하는 라인을 제외하고 새 파일에 저장합니다.
# 주의: 이 방법은 PS1= 로 시작하는 라인만 삭제합니다.
# PS1에 대한 주석이나 다른 복잡한 설정은 별도로 처리해야 할 수 있습니다.
if grep -qE '^\s*(export)?\s*PS1=' "$BASHRC_FILE"; then
    # 'export PS1=' 또는 'PS1=' 형태를 포함하는 라인(앞뒤 공백 허용)을 제외하고 덮어씁니다.
    grep -vE '^\s*(export)?\s*PS1=' "$BASHRC_FILE" > /tmp/bashrc_temp_ps1
    mv /tmp/bashrc_temp_ps1 "$BASHRC_FILE"
fi

# --- 3. 새로운 PS1 설정 추가 ---
# [hour:minute]마지막디렉토리$ 형태를 위한 PS1 문자열
# \t: HH:MM:SS
# \A: HH:MM
# \w: 현재 작업 디렉토리
# \W: 현재 작업 디렉토리의 마지막 구성 요소 (마지막 디렉토리 이름)
NEW_PS1='export PS1="[\A] \W$ "'

echo "" >> "$BASHRC_FILE"
echo "# Custom PS1: [hour:minute] LastDir\$" >> "$BASHRC_FILE"
echo "$NEW_PS1" >> "$BASHRC_FILE"

source ~/.bashrc
