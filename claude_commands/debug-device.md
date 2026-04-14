Diagnose why a XCENA device program failed (SIGBUS, segfault, kernel load error, etc.).

`$ARGUMENTS` is the path to the failing executable, optionally with its arguments (e.g., `./data_copy -n 4`).

## Steps

### 1. Reproduce the failure (with THP enabled)
First try running with THP enabled to isolate the failure:
```bash
# Build wrapper if needed
[ -x /tmp/thp_enable ] || gcc -O2 -o /tmp/thp_enable - << 'EOF'
#include <sys/prctl.h>
#include <unistd.h>
int main(int argc, char *argv[]) {
    prctl(PR_SET_THP_DISABLE, 0, 0, 0, 0);
    if (argc > 1) execv(argv[1], argv + 1);
    return 1;
}
EOF

/tmp/thp_enable <executable> [args...] 2>&1
echo "Exit code: $?"
```

### 2. Classify the failure by exit code / signal

| Exit code | Signal | Likely cause |
|---|---|---|
| 135 | SIGBUS (7) | DAX alignment fault — THP disabled, or misaligned mmap offset |
| 139 | SIGSEGV (11) | Null/invalid pointer, out-of-bounds memory access |
| 127 | — | Executable not found or missing shared library |
| 1 | — | Application-level error (check stderr) |
| 0 | — | Success (no bug) |

### 3. Collect kernel diagnostics
```bash
sudo dmesg | grep -E "device_dax|dax_fault|alignment|SIGBUS|segfault|pte_fault|huge_fault" | tail -20
```

Look for:
- `alignment (0x200000) > fault size (0x1000)` → order-0 fault on 2MB-aligned device; THP was disabled
- `dax_pgoff_to_phys.*failed` → mmap offset outside the DAX region
- `check_vma failed` → VMA not valid for device (MAP_PRIVATE used instead of MAP_SHARED)

### 4. Check THP state in parent chain
```bash
check_pid=$$
for i in $(seq 6); do
  name=$(awk '/^Name:/{print $2}' /proc/$check_pid/status 2>/dev/null)
  thp=$(awk '/^THP_enabled:/{print $2}' /proc/$check_pid/status 2>/dev/null)
  ppid=$(awk '/^PPid:/{print $2}' /proc/$check_pid/status 2>/dev/null)
  echo "PID $check_pid ($name): THP_enabled=$thp"
  [ "$ppid" = "0" ] && break; check_pid=$ppid
done
```

### 5. Verify DAX device health
```bash
ls -la /dev/dax*.*
find /sys/bus/cxl/devices -name "align" | while read f; do
  echo "$f = $(sudo cat $f 2>/dev/null)"
done
```

### 6. Check binary dependencies
```bash
ldd <executable>
# Look for "not found" entries
```
If `libpxl.so` is missing: ensure `LD_LIBRARY_PATH` includes `/sdk_release/lib/pxl/build/` or wherever it is installed.

### 7. Check kernel binary (.mubin)
```bash
ls -la mu_kernel/*.mubin 2>/dev/null || find . -name "*.mubin" | head -5
```
If `.mubin` is missing or stale: rebuild with pxcc.

### 8. Produce a diagnosis

Based on the evidence above, state:
- **Root cause**: what specifically failed
- **Fix**: concrete steps to resolve it
- **Verification**: how to confirm the fix worked

Common diagnoses:
- *THP disabled (Claude Code)*: Add `prctl(PR_SET_THP_DISABLE, 0, ...)` at program start, or use `/run-device`.
- *Stale .mubin*: Rebuild the MU kernel with pxcc.
- *Missing library*: Set `LD_LIBRARY_PATH` or rerun `install.sh`.
- *pxl_resourced not running*: Expected warning only; does not cause SIGBUS.
