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
├── launch_docker_container.sh  # Docker 컨테이너 셋업
├── config.sh                # 토큰 + 원격 정보 (skip-worktree, 빈 템플릿이 tracked)
├── .clangd                  # C++ LSP 설정 (mu_library 경로 포함)
├── .gitignore               # nvim/, sdk_release/, llvm-project/, shared/ 제외
├── nvim/                    # Neovim 설정 (init.lua, plugins, LSP)
├── remote/                  # 원격 머신 관리 스크립트 (lib.sh / setup.sh / check.sh / ssh_docker.sh / reset.sh)
├── docs/remote/             # 원격 디버깅/운영 문서
├── binaries/                # 워크어라운드용 사전빌드 바이너리 (예: xcena_cli.legacy)
├── sort/                    # SDK 예제 (CXL device 검증용)
├── .agents/skills/          # Claude skill 정의 (remote-setup/check/ssh-docker/reset 등)
├── cost_model/              # 비용 모델 관련 문서/자료
└── .devcontainer/           # Dev container 설정
```

## Environment Details

- `execute_with_source.sh`는 반드시 `source`로 실행 (subshell 불가)
- 토큰 + 원격 정보 (`GH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `REMOTE_IP/USER/PASSWORD`) 는 `config.sh` 한 곳에서 관리. `config.sh` 자체는 빈 템플릿이 git에 tracked, 실제 값은 `git update-index --skip-worktree config.sh` 로 로컬 변경 무시.
- 컨테이너 환경은 PS1 색상으로 구분 (Docker: 보라색, 호스트: 파란색)
- Claude alias: `claude --dangerously-skip-permissions`
- Remote alias (`config.sh` 활성화 후 `.bashrc`에 자동 등록): `remote_status / remote_on / remote_off`

## Remote XCENA 머신 관리

원격 device-호스트에서 컨테이너를 관리하는 헬퍼들 (`config.sh` 활성화 전제). 자세한 설명은 [`remote/README.md`](remote/README.md) 참조.

**일상**
```bash
bash remote/check.sh                 # 헬스체크 (host vs container device 비교 + sort 빌드)
bash remote/ssh_docker.sh '<cmd>'    # 컨테이너 안에서 명령 실행
bash remote/sync.sh                  # 로컬 → 원격 incremental rsync (dev 사이클 단축)
```

**진단**
```bash
bash remote/host_diag.sh             # host stack 스냅샷 (lsmod / device files / cxl / pxl)
bash remote/dmesg.sh [pattern]       # 원격 sudo dmesg + grep
bash remote/diag.sh                  # SDK 공식 troubleshooting.sh 다운/실행 + 보고서 회수
bash remote/log.sh                   # setup.log + journal + dmesg 한 디렉토리에 회수
```

**복구 / 변경**
```bash
bash remote/setup.sh                 # 처음 프로비저닝 (10–25분)
bash remote/reset.sh                 # BMC 전원 cycle + 자동 복구 (15–40분)
bash remote/apply_legacy_cli.sh      # 기존 컨테이너에 legacy xcena_cli 핫패치
bash remote/upgrade_host.sh          # host의 libpxl + driver 업그레이드 (30–60분, destructive)
```

Claude skills 도 등록되어 있어 자연어로도 호출 가능 (`remote-setup`, `remote-check`, `remote-ssh-docker`, `remote-reset`, `sdk-release-info`).

## Docs

- [`docs/remote/system_debugging.md`](docs/remote/system_debugging.md) — host/container 디바이스 인식 안 될 때 진단 + 호스트 stack 업그레이드 절차 + 알려진 함정. 원격 device 디버깅 시 가장 먼저 참고.

## Related Projects

이 워크스페이스에서 주로 작업하는 프로젝트:

- **PXCC** (`/sdk_release/tools/pxcc/`) — Heterogeneous C/C++ 컴파일러. 자체 CLAUDE.md 참조.
- **sdk_release** (`/sdk_release/`) — XCENA SDK. `git pull --ff-only && git submodule update --init --recursive` 하면 최신 libpxl/driver/cli 소스 + 공식 docs(install, troubleshooting) 확보 가능.

## Conventions

- 커밋 메시지: 한 줄 요약, 영어
- 스크립트: bash, 한글 주석 허용
- `.bashrc` 커스텀 설정은 `### jhkim-config start/end` 블록 안에서만 관리
