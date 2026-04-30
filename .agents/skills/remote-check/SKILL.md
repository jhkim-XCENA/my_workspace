---
name: remote-check
description: Health-check the remote XCENA machine — verifies power, SSH, host-level xcena_cli num-device, container status, container-level xcena_cli num-device (catches docker --privileged misconfig), deeper device probes (device-info / debug-error / fw-info), and a sort build/run smoke test. Use when the user asks to "check remote", "리모트 상태 확인", "원격 헬스체크", "리모트 점검", or wants to confirm device visibility inside docker.
---

# Remote Check

Run a layered health check on the remote machine:

1. **[0]** Power on + SSH reachable
2. **[1]** Host xcena_cli num-device (PCI/driver level — diagnoses lspci/lsmod if 0)
3. **[2]** Latest jhkim_* container exists and is `running`
4. **[3]** Container xcena_cli num-device — compares against host (host≥1 but container=0 → docker --privileged or /dev/mx_dma issue)
5. **[4]** Informational: `device-info 0` (MSUB Bitmap), `debug-error 0` (IRQ flags), `fw-info 0` (firmware revision)
6. **[5]** scp `sort/` and run `build.sh` + execute both binaries inside container

## How to invoke

```bash
bash /home/worker/remote/check.sh
```

## Prerequisites

- `config.sh` is filled in
- Remote is powered on with the container already created (run `setup.sh` if not)

## Diagnostic value

- Step 3 mismatch is the fastest way to detect that the docker container was started without `--privileged` or without `/dev/mx_dma` access
- Step 4 surfaces device-level errors that would otherwise show only as silent runtime failures during workloads
