Show the full health status of XCENA CXL/DAX devices in this environment.

Runs a series of diagnostic checks and presents a structured summary. No arguments needed.

## Steps

### 1. THP (Transparent Huge Pages) state
```bash
cat /sys/kernel/mm/transparent_hugepage/enabled
cat /proc/self/status | grep THP
```
- Flag if `THP_enabled: 0` — this causes SIGBUS when running device programs via Claude Code.
  Fix: use `/run-device` command or call `prctl(PR_SET_THP_DISABLE, 0)` in the program.

### 2. DAX device inventory
```bash
ls -la /dev/dax*.*  2>/dev/null
```
For each device found, show:
```bash
# Alignment requirement
sudo cat /sys/bus/cxl/devices/dax_region<N>/dax_region/align 2>/dev/null
# Or find it via:
find /sys/bus/cxl/devices -name "align" 2>/dev/null | while read f; do
  echo "$f: $(sudo cat $f 2>/dev/null)"
done
```

### 3. CXL region info
```bash
for r in /sys/bus/cxl/devices/region*; do
  name=$(basename $r)
  resource=$(sudo cat $r/resource 2>/dev/null | xargs printf "0x%x" 2>/dev/null)
  size=$(sudo cat $r/size 2>/dev/null | xargs printf "0x%x" 2>/dev/null)
  echo "$name: resource=$resource size=$size"
done
```

### 4. pxl_resourced daemon status
```bash
pgrep -a pxl_resourced || echo "pxl_resourced not running (standalone mode)"
ls /tmp/pxl/ 2>/dev/null
```
- If no daemon: programs run in standalone mode (warning printed, but functional).
- If stale pipes exist (`/tmp/pxl/client_*`, `/tmp/pxl/error_*`): clean them.

### 5. Recent device-related kernel messages
```bash
sudo dmesg | grep -E "device_dax|dax_open|dax_mmap|dax_release|cxl|SIGBUS|Bus error" | tail -20
```

### 6. Process environment summary
```bash
echo "Current user: $(whoami)"
echo "PID: $$"
# Walk parent chain for THP status
check_pid=$$
for i in $(seq 5); do
  name=$(awk '/^Name:/{print $2}' /proc/$check_pid/status 2>/dev/null)
  thp=$(awk '/^THP_enabled:/{print $2}' /proc/$check_pid/status 2>/dev/null)
  ppid=$(awk '/^PPid:/{print $2}' /proc/$check_pid/status 2>/dev/null)
  echo "  PID $check_pid ($name): THP_enabled=$thp"
  check_pid=$ppid
  [ -z "$ppid" ] || [ "$check_pid" = "0" ] && break
done
```

### 7. Summary table

Present a clean status table:

| Check | Status | Notes |
|---|---|---|
| DAX devices | found / not found | list device names |
| THP (system) | always / madvise / never | sysfs value |
| THP (this process) | enabled / **DISABLED** | from /proc/self/status |
| pxl_resourced | running / not running | standalone mode if not running |
| DAX alignment | 2MB / other | per device |

Highlight any issues that would prevent device programs from running correctly.
