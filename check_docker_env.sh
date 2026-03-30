#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

ERRORS=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pass() { echo -e "  ${GREEN}✔${NC} $1"; }
fail() { echo -e "  ${RED}✘${NC} $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }

echo "=== Dev Container 환경 점검 ==="
echo ""

# 1. 호스트 디렉토리/파일 존재 확인
echo "[1] 호스트 파일 및 디렉토리"

REQUIRED_DIRS=(
    "$HOME/.ssh"
    "$HOME/.claude"
)

CLAUDE_VERSIONS_DIR="$HOME/.local/share/claude/versions"
CLAUDE_BINARY="$CLAUDE_VERSIONS_DIR/$(ls -v "$CLAUDE_VERSIONS_DIR" 2>/dev/null | tail -1)"

REQUIRED_FILES=(
    "$HOME/.gitconfig"
    "$CLAUDE_BINARY"
    "$HOME/.claude/.credentials.json"
    "$HOME/.claude.json"
    "$SCRIPT_DIR/token.txt"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        pass "$dir"
    else
        fail "$dir 디렉토리 없음"
    fi
done

for file in "${REQUIRED_FILES[@]}"; do
    if [ -e "$file" ]; then
        pass "$file"
    else
        fail "$file 파일 없음"
    fi
done

# token.txt 내용 확인
if [ -e "$SCRIPT_DIR/token.txt" ]; then
    TOKEN="$(cat "$SCRIPT_DIR/token.txt" 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$TOKEN" ]; then
        pass "token.txt 내용 있음"
    else
        fail "token.txt 파일은 있으나 비어있음"
    fi
fi

echo ""

# 2. Docker
echo "[2] Docker"

if command -v docker &>/dev/null; then
    pass "docker 명령어 존재"
else
    fail "docker가 설치되지 않음"
fi

if docker info &>/dev/null 2>&1; then
    pass "docker 데몬 실행 중"
else
    fail "docker 데몬에 접근 불가 (실행 중인지, 권한이 있는지 확인)"
fi

IMAGE="192.168.57.60:8008/sdk_release/sdk_release:latest"
if docker image inspect "$IMAGE" &>/dev/null 2>&1; then
    pass "이미지 로컬에 존재: $IMAGE"
else
    warn "이미지 로컬에 없음: $IMAGE (pull 시도)"
    if docker pull "$IMAGE" &>/dev/null 2>&1; then
        pass "이미지 pull 성공"
    else
        fail "이미지 pull 실패: $IMAGE (레지스트리 접근 확인 필요)"
    fi
fi

if [ -e /dev/kvm ]; then
    pass "/dev/kvm 존재"
else
    fail "/dev/kvm 없음 (KVM 가상화 미지원 또는 모듈 미로드)"
fi

echo ""

# 결과 요약
echo "=== 점검 완료 ==="
if [ "$ERRORS" -eq 0 ]; then
    echo -e "${GREEN}모든 항목 통과. ./launch_docker_container.sh 로 컨테이너를 실행하세요.${NC}"
else
    echo -e "${RED}${ERRORS}개 항목 미충족. 위 내용을 확인하세요.${NC}"
    exit 1
fi
