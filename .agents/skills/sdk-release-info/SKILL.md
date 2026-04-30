---
name: sdk-release-info
description: Get the latest XCENA SDK info — pulls /sdk_release and updates submodules so the user can inspect libpxl source/deb, mx_dma kernel driver source, xcena_cli source, and official docs (install, troubleshooting). Use when the user asks about SDK internals, host driver/daemon mismatch, "최신 SDK 정보", "sdk 업데이트", "libpxl 버전", "mx_dma driver source", "xcena_cli 소스", or before debugging an unfamiliar SDK version.
---

# SDK Release Info (latest)

The local `/sdk_release` checkout is the authoritative source for **libpxl**, the **mx_dma kernel driver**, **xcena_cli** sources, and the official install/troubleshooting docs. Running a fresh pull + submodule update is the fastest way to confirm what version of each component is currently shipping and to grab the install scripts.

## How to invoke

```bash
cd /sdk_release && git pull --ff-only && git submodule update --init --recursive
```

## Where to find what

| 필요한 것 | 위치 |
|-----------|------|
| 최신 libpxl deb (host에 dpkg -i 가능) | `/sdk_release/lib/pxl/` (build via `lib/pxl/install.sh`) |
| 새 컨테이너 안 빌드된 libpxl deb | `<container>:/work/lib/pxl/libpxl_*.deb` (docker cp 로 추출) |
| mx_dma 커널 드라이버 소스 + DKMS conf + install.sh | `/sdk_release/driver/` (`bash install.sh` 로 빌드 + 적재) |
| xcena_cli 소스 (PyArmor + PyInstaller) | `/sdk_release/tools/cli/src/` |
| Docker run 옵션 가이드 (single + multi container) | `/sdk_release/docs/install/docker/` |
| 공식 troubleshooting 절차 + `troubleshooting.sh` 인용 | `/sdk_release/docs/troubleshooting.md` |
| 시스템 요구사항 (kernel, cxl, daxctl 버전 등) | `/sdk_release/docs/install/system_requirements.md` |

## When to use

- 호스트 `pxl_resourced` 와 컨테이너 `xcena_cli` 가 안 맞을 때 (버전 mismatch 가능성)
- 새 SDK 빌드가 어떤 커널 드라이버/libpxl/cli 버전을 묶고 있는지 빠르게 보고 싶을 때
- 공식 troubleshooting 단계 따라가 보고 싶을 때
- `troubleshooting.sh` 다운로드/실행 — `validate_host.sh` 결과만 봐도 PCI/CXL/DAX/Driver/PXL 한 줄 진단

## See also

`docs/remote/system_debugging.md` — 시행착오 기반 실전 디버깅 절차.
