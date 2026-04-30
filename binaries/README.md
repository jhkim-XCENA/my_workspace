# binaries/

워크어라운드용 사전 빌드 바이너리. SDK upstream 이 fix 되면 제거 예정.

## xcena_cli.legacy

| 항목 | 값 |
|------|-----|
| 출처 | `db-devenv` 이미지 (`192.168.57.60:8008/db-devenv/devenv:b0b39437` 추정) — `jhkim_db_silicon_260429_2` 컨테이너의 `/usr/local/bin/xcena_cli` |
| 추출일 | 2026-04-30 |
| 크기 | ~37MB |
| 버전 | (`--version` 없는 옛 빌드. xcena_cli 1.4 미만으로 추정) |
| 왜 필요한가 | 같은 호스트(libpxl 3.0.0, mx_dma driver, pxl_resourced 정상)에서 SDK 1.4.5 빌드의 `xcena_cli` 는 "Number of devices : 0 / No CXL devices found" 반환, 이 옛 binary 는 device 3개 정상 인식 |
| 어디서 사용 | `launch_docker_container.sh` 가 silicon 모드 컨테이너 생성 후 `xcena_cli num-device` 가 0 이면 자동 `docker cp` |
| 수동 적용 | `bash remote/apply_legacy_cli.sh [container]` |
| 언제 제거 | sdk_release 의 새 `xcena_cli` 빌드가 device 정상 인식할 때. 검증 방법: 임의 SDK 컨테이너에서 직접 `xcena_cli num-device` 실행해 N≥1 나오면 — `launch_docker_container.sh` 의 sanity check step 도 함께 제거 |

## 주의

- **이 디렉토리에 사용자 입력 (token, password) 두지 말 것**. 단일 목적 워크어라운드 바이너리만.
- 새 워크어라운드 바이너리 추가 시 위 표 형식으로 항목 추가하고, `launch_docker_container.sh` 의 fallback 로직도 함께 갱신.
