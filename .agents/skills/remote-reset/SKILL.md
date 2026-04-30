---
name: remote-reset
description: Power-cycle the remote XCENA machine via the BMC API and recover the docker container. Use when the user says "리모트 재부팅", "원격 reset", "리모트 머신 다시 켜줘", "전원 재시작", "리셋해줘", or when the machine is hung and a clean off/on cycle is needed. Automatically falls through to docker start or setup.sh if the container is gone.
---

# Remote Reset

Hard power cycle + recovery for the remote XCENA machine. After power-on, SSH may take 5–15 min to become reachable (OS boot + sshd) — the script handles this wait.

## How to invoke

```bash
bash /home/worker/remote/reset.sh
```

## What it does

1. **Power off** — up to 5 attempts × 5 min wait (BMC sometimes ignores the first off command)
2. **Power on** — wait up to 10 min for power state
3. **Wait for SSH** — up to 15 min (OS boot + sshd)
4. **Recovery branch**:
   - run `check.sh` → if pass, done
   - if a stopped `jhkim_*` container exists → `docker start` and re-run `check.sh`
   - if no container → fall through to `setup.sh` (full provisioning)

## Expected runtime

15–40 minutes depending on whether docker start is enough or full setup.sh kicks in.

## When NOT to use

- If only the docker container is wedged but the machine is fine — `docker_exec` may suffice (or `ssh_docker.sh "..."`)
- For a fresh install with no prior container ever created — use `setup.sh` directly (faster, skips the off/on cycle)
