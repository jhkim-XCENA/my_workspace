# CLAUDE.md

This file provides guidance to Claude Code when working in this workspace.

## Repository Overview

**my_workspace** — 개발 환경 설정 레포 (Neovim, Docker, Claude Code). 호스트/컨테이너 환경 자동 구성을 위한 스크립트와 설정 파일을 관리한다.

## Quick Start

```bash
# 호스트 환경 직접 설치
source ./execute_with_source.sh

# Docker 환경
./launch_docker_container.sh
```

## Project Structure

```
~/
├── execute_with_source.sh   # 전체 환경 설정 (source로 실행)
├── github_token.txt         # GitHub token (git-ignored)
├── claude_token.txt         # Claude OAuth token (git-ignored)
├── .clangd                  # C++ LSP 설정 (mu_library 경로 포함)
├── .gitignore               # nvim/, sdk_release/, llvm-project/, shared/ 제외
├── nvim/                    # Neovim 설정 (init.lua, plugins, LSP)
├── cost_model/              # 비용 모델 관련 문서/자료
└── .devcontainer/           # Dev container 설정
```

## Environment Details

- `execute_with_source.sh`는 반드시 `source`로 실행 (subshell 불가)
- GitHub token: `github_token.txt`에서 읽어 `GITHUB_TOKEN`, `GH_TOKEN` 환경변수로 설정
- Claude token: `claude_token.txt`에서 읽어 `CLAUDE_CODE_OAUTH_TOKEN` 환경변수로 설정
- 컨테이너 환경은 PS1 색상으로 구분 (Docker: 보라색, 호스트: 파란색)
- Claude alias: `claude --dangerously-skip-permissions`

## Related Projects

이 워크스페이스에서 주로 작업하는 프로젝트:

- **PXCC** (`/sdk_release/tools/pxcc/`) — Heterogeneous C/C++ 컴파일러. 자체 CLAUDE.md 참조.

## Conventions

- 커밋 메시지: 한 줄 요약, 영어
- 스크립트: bash, 한글 주석 허용
- `.bashrc` 커스텀 설정은 `### jhkim-config start/end` 블록 안에서만 관리
