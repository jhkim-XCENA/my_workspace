# Remote XCENA System / Container Debugging

원격 머신(`REMOTE_IP`) + Docker 컨테이너에서 XCENA device가 안 보이거나 동작이 이상할 때 절차. 2026-04-30 디버깅 세션에서 얻은 경험을 기반으로 작성.

> Note: 모든 명령은 `source ./execute_with_source.sh` 후 `REMOTE_IP/USER/PASSWORD` 가 환경변수로 활성화된 상태를 전제로 한다. `bash /home/worker/remote/check.sh` 가 가장 빠른 한 번에 진단 도구. 그래도 원인이 안 잡히면 아래 절차로.

---

## 1. 1차 진단 — `check.sh` + `troubleshooting.sh`

### 1.1 자체 헬스체크
```bash
bash /home/worker/remote/check.sh
```

각 단계 의미:

| 단계 | 검사 항목 | fail 시 의심 |
|------|-----------|---------------|
| [0] | Power + SSH | BMC 또는 OS 부팅 문제 → `reset.sh` |
| [1] | host `xcena_cli num-device` | host 드라이버/데몬/인프라 |
| [2] | `jhkim_*` 컨테이너 존재 + running | `setup.sh` 또는 `docker start` |
| [3] | container `xcena_cli num-device`, host와 매칭 | docker `--privileged` / `/tmp/pxl` 마운트 / `xcena_cli` 버전 mismatch |
| [4] | device-info / debug-error / fw-info | 정보성 (실패해도 stop 안 함) |
| [5] | sort 빌드/실행 | sort 소스 ↔ libpxl API 호환성 |

### 1.2 SDK 공식 troubleshooting 스크립트
```bash
bash /home/worker/remote/ssh_docker.sh 'wget -q https://raw.githubusercontent.com/xcena-dev/public_sdk_release/refs/heads/main/scripts/troubleshooting.sh -O /tmp/ts.sh && bash /tmp/ts.sh'
```
또는 host에서 직접:
```bash
sshpass -p "$REMOTE_PASSWORD" ssh "$REMOTE_USER@$REMOTE_IP" 'cd /tmp && wget -q https://raw.githubusercontent.com/xcena-dev/public_sdk_release/refs/heads/main/scripts/troubleshooting.sh -O ts.sh && bash ts.sh'
```
첫 섹션 `validate_host.sh` 결과가 핵심 — PCI/CXL/DAX/Driver/PXL Library/CLI 가 OK인지 한눈에 확인 가능.

---

## 2. 호스트 vs 컨테이너 비교 (Step 3 fail 시)

### 2.1 `host num=N, container=0` 패턴 — privilege/mount 문제
```bash
# 컨테이너 옵션 확인
sshpass -p "$REMOTE_PASSWORD" ssh "$REMOTE_USER@$REMOTE_IP" \
  'docker inspect <CONTAINER> --format "Privileged={{.HostConfig.Privileged}} PidMode={{.HostConfig.PidMode}} UsernsMode={{.HostConfig.UsernsMode}}"'

# 컨테이너 안 /tmp/pxl, /sys/fs/cgroup
bash /home/worker/remote/ssh_docker.sh 'ls /tmp/pxl/; ls /sys/fs/cgroup/ | head'
```
**필수 옵션** (`launch_docker_container.sh`에 이미 반영됨):
- `--privileged --cap-add=SYS_ADMIN`
- `--pid=host --userns=host`
- `-v /tmp/pxl:/tmp/pxl`

### 2.2 `host=0, container=0` 패턴 — host stack 문제 (아래 §3)

### 2.3 `host=N, container=0` + 옵션 다 OK — `xcena_cli` 버전 mismatch
이번 세션에서 확인된 패턴: SDK 1.4.5 (오늘 빌드 sdk_release:latest) 의 `xcena_cli` binary가 host stack(드라이버/데몬 포함)이 정상이어도 0개로 보고. db-devenv 이미지의 옛 `xcena_cli`는 정상 동작.

**워크어라운드 (자동 적용)**: `binaries/xcena_cli.legacy` 가 `launch_docker_container.sh` step 후반에 자동으로 컨테이너에 `docker cp` 됨. fix 시 해당 step 제거.

---

## 3. Host stack 진단 (host=0 인 경우)

순서대로 확인.

### 3.1 PCI / 드라이버
```bash
sshpass -p "$REMOTE_PASSWORD" ssh "$REMOTE_USER@$REMOTE_IP" '
  lspci | grep -i CXL                          # 3개 (vendor 20a6) 보여야 함
  for bdf in 0000:15:00.0 0000:95:00.0 0000:b8:00.0; do
    echo "$bdf -> $(readlink /sys/bus/pci/devices/$bdf/driver | xargs basename)"
  done                                          # 모두 cxl_pci 에 bound
  lsmod | grep -E "mx_dma|cxl_"                # cxl_pmem,cxl_acpi,cxl_mem,cxl_port,cxl_pci,cxl_core,mx_dma 다 로드
  ls /dev/mx_dma/                               # mx_dma{0,1,2}_{bdf,context,data,event,ioctl} 15개
  ls /dev/dax*                                  # dax0.0, dax12.0, dax13.0
'
```

### 3.2 CXL 토폴로지
```bash
sshpass -p "$REMOTE_PASSWORD" ssh "$REMOTE_USER@$REMOTE_IP" '
  cxl list -R                                   # region0/12/13 with decode_state="commit"
  daxctl list                                   # 3개 dax devdax mode
'
```

### 3.3 데몬 + libpxl
```bash
sshpass -p "$REMOTE_PASSWORD" ssh "$REMOTE_USER@$REMOTE_IP" '
  systemctl is-active pxl_resourced
  pxl_resourced --version                       # pxl 3.0.0 이상
  dpkg -l libpxl                                # 3.0.0
  ls /tmp/pxl/                                  # service_pipe + history.log 존재
'
```

### 3.4 dmesg
```bash
sshpass -p "$REMOTE_PASSWORD" ssh "$REMOTE_USER@$REMOTE_IP" 'sudo dmesg | grep -iE "mx_dma|cxl.*err|cxl.*fail" | tail -30'
```
정상 부팅 시 `mx_dma{0,1,2}_* (M:N) is created` + `pci device is probed (vendor=0x20a6 ...)` 줄 3개씩 표시되어야 함.

---

## 4. 호스트 stack 업그레이드 절차 (sdk 1.4.5+ 기준)

호스트의 `libpxl`/`mx_dma` 드라이버가 컨테이너의 SDK 버전과 어긋날 때. 컨테이너의 `/work/lib/pxl/libpxl_*.deb` 와 `/work/driver/` 가 재료.

> ⚠️ 이 절차는 **다른 사용자가 host driver/daemon을 사용 중이라면 모든 컨테이너의 device 접근이 끊긴다.** 단독 사용 시점에 진행.

```bash
# 1. 새 deb + driver 추출 (컨테이너에서)
docker cp <NEW_SDK_CONTAINER>:/work/driver /tmp/mx_dma_driver_v3
docker cp <NEW_SDK_CONTAINER>:/work/lib/pxl/libpxl_*.deb /tmp/

# 2. 의존 컨테이너 + 데몬 중단
docker stop $(docker ps -q --filter name=^jhkim_)
sudo systemctl stop pxl_resourced
sudo pkill -9 -f pxl_resourced            # 잔여 프로세스 청소
sudo rmmod mx_dma                          # ref count 0 확인 후 unload

# 3. 새 driver 설치 (DKMS or legacy)
cd /tmp/mx_dma_driver_v3 && sudo bash install.sh

# 4. 새 libpxl + 데몬 재시작
sudo dpkg -i /tmp/libpxl_*.deb
sudo systemctl restart pxl_resourced
pxl_resourced --version                    # 새 버전 확인

# 5. PCI rebind 으로 mx_dma notifier 트리거 (또는 reboot — reboot 권장)
for bdf in 0000:15:00.0 0000:95:00.0 0000:b8:00.0; do
    sudo bash -c "echo $bdf > /sys/bus/pci/drivers/cxl_pci/unbind"
    sudo bash -c "echo $bdf > /sys/bus/pci/drivers/cxl_pci/bind"
done
ls /dev/mx_dma                             # 15개 device file 재생성 확인

# 6. 검증
xcena_cli num-device
```

**중요**: PCI rebind은 CXL region 토폴로지를 망가뜨릴 수 있다 (cxl list -R 이 비게 됨). reboot이 항상 가장 안전. 본 머신은 BMC API 로 reboot 가능:
```bash
bash /home/worker/remote/reset.sh
```

---

## 5. 새 SDK 정보 파악 (가장 빠른 방법)

```bash
cd /sdk_release && git pull --ff-only && git submodule update --init --recursive
```
- 최신 `lib/pxl/` (libpxl 소스 + deb 패키징)
- 최신 `driver/` (mx_dma 커널 드라이버 + DKMS conf + install.sh)
- 최신 `tools/cli/` (xcena_cli 소스 — PyArmor + PyInstaller)
- 최신 `docs/install/`, `docs/troubleshooting.md`

자세한 설치 옵션: `/sdk_release/lib/pxl/install.sh --help`, `/sdk_release/driver/install.sh`.

---

## 6. 자주 만나는 함정

| 증상 | 원인 | 해결 |
|------|------|------|
| `current working directory is outside of container mount namespace root` (docker exec -w) | `--userns=host` + `-w` 조합 docker bug | `-w` 제거하고 `bash -lc 'cd /home/worker && CMD'` 형태로 (lib.sh의 `rdocker_exec` 가 이미 처리) |
| `xcena_cli num-device → 0` (host도 0) | mx_dma driver 미로드 / cxl_pci 오바인딩 / pxl_resourced 죽음 | §3, §4 순서로 |
| `xcena_cli num-device → 0` (host = N, container = 0) | docker `--privileged`/`/tmp/pxl` 누락 또는 SDK 버전 mismatch | §2 |
| `cxl list -R` 비어있음 | 부팅 시 CXL 토폴로지 형성 실패 (PCI rebind 후 흔함) | reboot |
| `mx_dma is in use` (rmmod 실패) | 컨테이너/데몬이 fd 들고 있음 | docker stop + `sudo pkill -f pxl_resourced` |
| GitHub Push Protection (token leak) | config.sh에 실제 토큰 commit | `git update-index --skip-worktree config.sh` 후 빈 템플릿 commit |
| sort 빌드 OK / 실행 시 `Failed to create context` | 옛 sort 소스 ↔ 새 libpxl API mismatch (예: `pxl::Result` → `pxl::runtime::Result`) | 새 sample 코드로 교체 또는 sort 소스 수정 |

---

## 7. 알려진 미해결 이슈 (2026-04-30 기준)

1. **SDK 1.4.5의 `xcena_cli` binary가 정상 host stack에서도 0 devices** — db-devenv 이미지의 옛 `xcena_cli` 와 같은 host에서 비교 검증됨. `binaries/xcena_cli.legacy` 자동 fallback으로 우회. 해당 SDK 빌드 fix 시 fallback 제거 필요.
2. **`/work/example/sort/`** 의 코드는 옛 pxl API 기준 — pxl 3.0.0 헤더와 namespace 다름 (`pxl::Result` vs `pxl::runtime::Result`). 빌드는 되지만 런타임 실패.

---

## 참고

- `bash /home/worker/remote/check.sh` — 한 번에 헬스체크
- `bash /home/worker/remote/ssh_docker.sh '<cmd>'` — 컨테이너 안 명령
- `bash /home/worker/remote/reset.sh` — BMC 전원 cycle + 자동 복구
- `bash /home/worker/remote/setup.sh` — 처음 셋업 (또는 컨테이너 폐기 후 재구축)
- `/sdk_release/docs/troubleshooting.md` — XCENA 공식 문서
- `/sdk_release/docs/install/docker/multiple-containers.md` — 멀티컨테이너 (pxl_resourced) 가이드
