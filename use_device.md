# Running DAX/CXL Device Programs from Claude Code

## Background

When using Claude Code's Bash tool to run programs that access CXL memory (DAX devices such as `/dev/dax0.0`), you may encounter a **Bus Error (SIGBUS, exit code 135)** even though the exact same program runs successfully in your own shell.

This document explains the root cause, the full diagnosis path, and the required workaround.

---

## Symptom

```
$ cd ~/example/data_copy && ./data_copy   # run by Claude Code → SIGBUS (exit 135)
$ ./data_copy                             # run directly in your shell → success
```

dmesg shows:
```
device_dax:dev_dax_huge_fault: data_copy: write (...) order:0
device_dax:__dev_dax_pte_fault: alignment (0x200000) > fault size (0x1000)
```

---

## Root Cause

### 1. Claude Code disables THP via `prctl`

Claude Code (running as a Node.js process) calls:
```c
prctl(PR_SET_THP_DISABLE, 1, ...)
```
This sets the `MMF_DISABLE_THP` bit in its own memory-management descriptor (`mm_struct`).

### 2. The flag is inherited through `fork` + `exec`

When Claude Code spawns a subprocess (e.g., a shell to run your command), the following happens:

1. **`fork()`** — the child inherits the parent's mm, including `MMF_DISABLE_THP = 1`.
2. **`exec()`** — a new `mm_struct` is allocated via `mm_alloc()`. However, `mm_init()` copies flags matching `MMF_INIT_MASK` from the *current* (pre-exec) mm into the new one. `MMF_DISABLE_THP` is part of `MMF_INIT_MASK` (see `include/linux/sched/coredump.h` in the Linux kernel source):

```c
#define MMF_INIT_MASK  (MMF_DUMPABLE_MASK | MMF_DUMP_FILTER_MASK | \
                        MMF_DISABLE_THP_MASK | MMF_HAS_MDWE_MASK | ...)
```

So every program spawned by Claude Code, including your device program after all the `exec` calls in the shell pipeline, runs with THP disabled.

You can confirm this:
```bash
cat /proc/self/status | grep THP
# THP_enabled:  0    ← inside Claude Code's shell
```
vs. your own shell:
```bash
cat /proc/self/status | grep THP
# THP_enabled:  1    ← in your direct shell
```

### 3. Why THP matters for DAX devices

CXL DAX devices (`/dev/dax*.0`) are configured with a 2 MB alignment (`dax_region/align = 2097152`). The device-dax driver (`drivers/dax/device.c`) requires that page faults be serviced at PMD order (order 9, 2 MB) or PUD order (order 18, 1 GB):

```c
// __dev_dax_pte_fault — called when order == 0
if (dev_dax->align > PAGE_SIZE) {
    dev_dbg(..., "alignment (%#x) > fault size (%#x)\n", ...);
    return VM_FAULT_SIGBUS;   // ← triggers SIGBUS
}
```

The kernel only attempts PMD/PUD-level faults via `create_huge_pmd()` / `create_huge_pud()` when `thp_vma_allowable_order()` returns non-zero. That function calls `vma_thp_disabled()`, which returns `true` when `MMF_DISABLE_THP` is set:

```c
static inline bool vma_thp_disabled(struct vm_area_struct *vma,
                                     unsigned long vm_flags)
{
    return (vm_flags & VM_NOHUGEPAGE) ||
           test_bit(MMF_DISABLE_THP, &vma->vm_mm->flags);  // ← true here
}
```

With THP disabled → `thp_vma_allowable_order()` returns 0 → `create_huge_pmd` is never called → kernel falls through to `handle_pte_fault` → order:0 (4 KB) fault → SIGBUS.

### Complete fault path (confirmed via ftrace)

```
__handle_mm_fault
  └─ thp_vma_allowable_order(PMD_ORDER) == 0  ← THP disabled, skipped
  └─ handle_pte_fault
       └─ __do_fault
            └─ dev_dax_fault          (order 0)
                 └─ dev_dax_huge_fault (order 0)
                      └─ __dev_dax_pte_fault
                           └─ VM_FAULT_SIGBUS  ← 2MB align > 4KB fault
```

**With THP enabled** (user's direct shell, or after the fix below):
```
__handle_mm_fault
  └─ thp_vma_allowable_order(PUD_ORDER) → non-zero
  └─ create_huge_pud → dev_dax_huge_fault (order 18, 1 GB)
       └─ __dev_dax_pud_fault → success
```

---

## Fix / Workaround

### Option 1: `prctl` wrapper (immediate, no SDK changes)

Create a small C helper that re-enables THP, then `exec`s the target program:

```c
// thp_enable.c
#include <stdio.h>
#include <sys/prctl.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    prctl(PR_SET_THP_DISABLE, 0, 0, 0, 0);  // re-enable THP
    if (argc > 1)
        execv(argv[1], argv + 1);
    return 1;
}
```

```bash
gcc -o ~/thp_enable thp_enable.c
~/thp_enable ~/example/data_copy/data_copy   # works from Claude Code
```

### Option 2: Fix in the SDK / application (recommended)

Add the following call at the start of the program (or inside the SDK's device-init path) before any DAX `mmap`:

```c
#include <sys/prctl.h>

// In main() or SDK init:
prctl(PR_SET_THP_DISABLE, 0, 0, 0, 0);
```

This is the cleanest fix because it makes the program self-contained and does not depend on the launch environment.

### Option 3: Shell alias / wrapper script

```bash
# In your shell or script:
bash -c 'prctl ...'  # bash can't call prctl directly, use the C helper above
```

---

## Verification

After applying the fix, dmesg should show **order:18** (1 GB huge page) or **order:9** (2 MB huge page), not order:0:

```
device_dax:dev_dax_huge_fault: data_copy: write (...) order:18
```

And the program exits with code 0.

---

## Environment

| Component | Details |
|---|---|
| Kernel | Linux 6.8.0-88-generic (Ubuntu) |
| DAX devices | `/dev/dax0.0`, `/dev/dax12.0`, `/dev/dax13.0` |
| DAX alignment | 2 MB (`dax_region/align = 2097152`) |
| CXL region size | ~233 GB per region |
| Claude Code version | runs as Node.js process |

## Key kernel references

- `mm/memory.c` — `__handle_mm_fault`: PUD/PMD huge fault attempt gated by `thp_vma_allowable_order`
- `mm/huge_memory.c` — `__thp_vma_allowable_orders`: returns 0 when `vma_thp_disabled` is true
- `include/linux/sched/coredump.h` — `MMF_INIT_MASK` includes `MMF_DISABLE_THP_MASK`, causing the flag to survive `exec`
- `drivers/dax/device.c` — `__dev_dax_pte_fault`: returns `VM_FAULT_SIGBUS` when `align > PAGE_SIZE`
