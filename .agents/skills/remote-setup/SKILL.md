---
name: remote-setup
description: Provision the remote XCENA machine from scratch — clones my_workspace, syncs config.sh, launches the docker container, verifies with check. Use this when the user asks to "set up remote", "원격 셋업", "리모트 머신 새로 깔아줘", "리모트 프로비저닝", or after a full power-cycle when no container exists yet.
---

# Remote Setup

Provision the remote XCENA machine end-to-end. Use this skill when the user wants a fresh install on the remote — typically the first time, or after the container is permanently gone.

## How to invoke

Run the script from the local workspace:

```bash
bash /home/worker/remote/setup.sh
```

## What it does

1. Verifies remote power is on; waits up to 15 min for SSH (OS boot is slow after a fresh power-on)
2. `git clone --depth 1 git@github.com:jhkim-XCENA/my_workspace.git` to `/tmp/my_workspace.$$`
3. Regenerates `config.sh` from the current shell's env (`GH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `REMOTE_IP/USER/PASSWORD`) — writes both to the local `/home/worker/config.sh` and the tmp dir
4. SCPs the workspace to `/home/$REMOTE_USER/my_workspace/` on the remote
5. Runs `source ./launch_docker_container.sh` on the remote (creates a `jhkim_*` container)
6. Invokes `check.sh` to verify

## Prerequisites

- Current shell has `REMOTE_IP`, `REMOTE_USER`, `REMOTE_PASSWORD`, `GH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN` exported (run `source ./execute_with_source.sh` if not)
- Remote machine is powered on (otherwise run `reset.sh` first)
- Local has `sshpass`, `git`, `scp`

## Expected runtime

10–25 minutes depending on git clone, scp size, and `launch_docker_container.sh` build steps inside the container.
