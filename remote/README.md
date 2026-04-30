# remote/

원격 XCENA host (`REMOTE_IP`) + 그 위 Docker 컨테이너 관리 스크립트 모음.

## 전제

- `source ./execute_with_source.sh` 로 `config.sh` (REMOTE_IP/USER/PASSWORD/GH_TOKEN/CLAUDE_CODE_OAUTH_TOKEN) 가 환경변수에 활성화되어 있어야 함
- `sshpass` 설치되어 있어야 함 (execute_with_source.sh 의 prerequisite)
- 원격 host의 `/home/$REMOTE_USER/` 에 `my_workspace` 가 셋업되어 있어야 함 (`setup.sh` 가 처음 셋업)

## 스크립트

### 일상 작업

| 스크립트 | 용도 | 소요 시간 |
|----------|------|-----------|
| [`check.sh`](check.sh) | 헬스체크: power/ssh + host vs container `xcena_cli num-device` 비교 + sort 빌드 | 30초 ~ 2분 |
| [`ssh_docker.sh`](ssh_docker.sh) `'<cmd>'` | 최신 jhkim_* 컨테이너 안에서 명령 실행 (TTY) | 명령에 따라 |
| [`sync.sh`](sync.sh) | 로컬 워크스페이스 → 원격 incremental rsync (개발 사이클 단축) | 수 초 |

### 진단

| 스크립트 | 용도 |
|----------|------|
| [`diag.sh`](diag.sh) | SDK 공식 `troubleshooting.sh` 다운/실행 + 로컬로 보고서 회수 + 핵심 라인 요약 |
| [`host_diag.sh`](host_diag.sh) | host stack 스냅샷: lsmod / /dev/mx_dma / /dev/dax / PCI bindings / cxl list / daxctl / pxl_resourced / xcena_cli (docs/remote/system_debugging.md §3 자동화) |
| [`dmesg.sh`](dmesg.sh) `[pattern]` | 원격 `sudo dmesg` + 패턴 grep (기본: mx_dma\|cxl\|xcena\|err\|fail\|warn) |
| [`log.sh`](log.sh) | 원격 setup.log + container setup.log + pxl_resourced journal + dmesg + host_diag 한 디렉토리에 회수 |

### 복구 / 변경

| 스크립트 | 용도 | 소요 시간 |
|----------|------|-----------|
| [`setup.sh`](setup.sh) | 처음 프로비저닝: clone → config 동기화 → SSH key 동기화 → wipe-and-recreate scp → docker launch → check.sh | 10–25분 |
| [`reset.sh`](reset.sh) | BMC 전원 cycle (off×5 재시도 → on → SSH wait 15분) → check.sh → docker start fallback → setup.sh fallback | 15–40분 |
| [`apply_legacy_cli.sh`](apply_legacy_cli.sh) `[container]` | 이미 떠 있는 컨테이너에 `binaries/xcena_cli.legacy` 핫패치 (SDK 1.4.5 cli 버그 우회용 — `launch_docker_container.sh` 가 새 컨테이너에는 자동 적용) | 수 초 |
| [`upgrade_host.sh`](upgrade_host.sh) `[container] [--yes]` | 컨테이너에서 libpxl deb + mx_dma 드라이버 추출 → host 설치 → BMC reboot. **다른 컨테이너 device 접근 끊김** | 30–60분 |

### 공통 라이브러리

| 파일 | 내용 |
|------|------|
| [`lib.sh`](lib.sh) | `load_config`, `log_*`, `power_status/on/off`, `is_device_on`, `wait_for_state`, `wait_for_ssh`, `rssh/_tty`, `rscp`, `RHOST`, `remote_latest_container`, `remote_container_status`, `rdocker_exec/_tty` |

각 스크립트 첫 줄에서 `source "$(dirname "$0")/lib.sh"` 로 로드.

## 함정 / 주의

- **userns=host + `docker exec -w`**: docker bug 로 cwd 해석 실패. lib.sh의 `rdocker_exec` 가 `cd /home/worker` 로 우회. 외부에서 직접 `docker exec -w /home/worker ...` 호출 금지.
- **`upgrade_host.sh` 는 destructive**: 모든 jhkim_* 컨테이너 stop + pxl_resourced 죽임. 다른 사용자에게 영향. 단독 사용 시점에만.
- **PCI unbind/rebind 후 `cxl list -R` 비어있음**: 거의 항상 reboot 필요 (런타임 복구 불가).
- **SDK 1.4.5 `xcena_cli` 버그**: host stack 정상에서도 0 devices 보고. `binaries/xcena_cli.legacy` 자동 fallback. 자세한 내용은 `docs/remote/system_debugging.md` 참조.

## 더 자세히

- [`docs/remote/system_debugging.md`](../docs/remote/system_debugging.md) — host/container device 디버깅 절차
- [`/sdk_release/docs/troubleshooting.md`](/sdk_release/docs/troubleshooting.md) — XCENA 공식 troubleshooting (sdk-release-info skill 로 git pull 후 참조)
