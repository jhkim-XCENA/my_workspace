---
name: remote-ssh-docker
description: Run an arbitrary command inside the latest jhkim_* docker container on the remote XCENA machine. Use when the user says "리모트 도커에서 X 실행", "ssh docker", "원격 컨테이너에서 명령", "remote container shell", or wants to inspect/debug something inside the running container without manually composing ssh + docker exec.
---

# Remote SSH Docker

Thin wrapper for "ssh into the remote, then docker exec into the latest jhkim_* container, then run this command". TTY allocated; runs as the `worker` user with cwd `/home/worker`.

## How to invoke

```bash
bash /home/worker/remote/ssh_docker.sh '<command string>'
```

Examples:
```bash
bash /home/worker/remote/ssh_docker.sh 'xcena_cli num-device'
bash /home/worker/remote/ssh_docker.sh 'cd /home/worker/sort && ./build.sh'
bash /home/worker/remote/ssh_docker.sh 'env | grep MU_'
```

## Notes

- Single-pass shell quoting via `printf '%q'` — handles common shell metacharacters but very complex pipelines may need a different approach
- Uses the latest container by Docker creation time (newest `jhkim_*`)
- For non-interactive scripted use within other automation, prefer the `rdocker_exec` function from `lib.sh`
