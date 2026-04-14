# Claude Commands — XCENA SDK / Device Development

Custom Claude Code slash commands for XCENA SDK and CXL device development.

Place this directory at `~/.claude/commands/` or reference it from `.claude/commands/` in your project to activate these commands.

## Commands

| Command | Usage | Description |
|---|---|---|
| `/run-device` | `/run-device ./data_copy -n 8` | Run a device program with THP correctly re-enabled (fixes Claude Code SIGBUS) |
| `/device-status` | `/device-status` | Health check: DAX devices, CXL regions, THP state, pxl_resourced, dmesg |
| `/debug-device` | `/debug-device ./data_copy` | Diagnose SIGBUS, segfault, kernel load errors in device programs |
| `/new-xcena-app` | `/new-xcena-app my_filter` | Scaffold a new app with host (PXL) + kernel (MU) boilerplate |
| `/build` | `/build` or `/build Debug` | Build the CMake project in the current directory |
| `/sdk-example` | `/sdk-example sort` | Build and run an SDK example (sort, data_copy, vector, …) |
| `/review-mu-kernel` | `/review-mu-kernel mu_kernel/` | Review MU kernel code for correctness and constraint compliance |
| `/gh-issue` | `/gh-issue sdk_release SIGBUS in data_copy` | File a GitHub issue to any xcena-dev repo |

## Key Background: Claude Code SIGBUS Fix

Claude Code's Node.js process sets `prctl(PR_SET_THP_DISABLE, 1)`, which propagates
through `fork+exec` into all child processes (via `MMF_INIT_MASK`). This disables
Transparent Huge Pages for all subprocesses, causing DAX page faults to be serviced
at 4 KB (order 0) instead of 2 MB (PMD order 9), which the CXL DAX device rejects
with `VM_FAULT_SIGBUS`.

**Fix**: call `prctl(PR_SET_THP_DISABLE, 0, 0, 0, 0)` at program start, or use
`/run-device` which wraps any binary with this call automatically.

See `~/use_device.md` (English) and `~/use_device_ko.md` (Korean) for the full analysis.
