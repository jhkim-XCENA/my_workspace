Run a XCENA device program from Claude Code with THP correctly enabled.

`$ARGUMENTS` is the path to the executable, optionally followed by its arguments (e.g., `./data_copy -n 8 -d 0`).

## Background

Claude Code's Node.js process sets `prctl(PR_SET_THP_DISABLE, 1)`, which propagates through `fork+exec` into all child processes (via `MMF_INIT_MASK` in `mm_init`). With THP disabled, the Linux kernel skips PMD/PUD-level DAX page faults and falls through to 4 KB order-0 faults, which the device-dax driver rejects with `VM_FAULT_SIGBUS` because the CXL DAX device requires 2 MB alignment. This wrapper re-enables THP before executing the target program.

See `use_device.md` for the full root-cause analysis.

## Steps

1. **Check THP state**:
   ```bash
   cat /proc/self/status | grep THP
   ```
   Report whether THP is currently enabled or disabled for this process.

2. **Verify the target binary exists**:
   Parse `$ARGUMENTS` to extract the executable path (first token). Check that it exists and is executable:
   ```bash
   ls -la <executable>
   ```
   If not found, report the error and stop.

3. **Check device availability**:
   ```bash
   ls /dev/dax*.* 2>/dev/null || echo "No DAX devices found"
   sudo dmesg | grep -i "dax\|cxl" | tail -5
   ```

4. **Build the THP-enable wrapper** (build once, reuse if already exists):
   ```bash
   if [ ! -x /tmp/thp_enable ]; then
     cat > /tmp/thp_enable.c << 'EOF'
   #include <sys/prctl.h>
   #include <unistd.h>
   int main(int argc, char *argv[]) {
       prctl(PR_SET_THP_DISABLE, 0, 0, 0, 0);
       if (argc > 1) { execv(argv[1], argv + 1); }
       return 1;
   }
   EOF
     gcc -O2 -o /tmp/thp_enable /tmp/thp_enable.c
   fi
   ```

5. **Run the program** with THP re-enabled:
   ```bash
   /tmp/thp_enable <executable> [args...]
   ```
   Capture stdout and stderr. Show the full output.

6. **On failure (non-zero exit)**:
   - Check exit code: 135 = SIGBUS (likely still a device fault issue)
   - Show recent dmesg:
     ```bash
     sudo dmesg | grep -E "device_dax|dax_fault|SIGBUS|Bus error" | tail -10
     ```
   - Report the failure with context.

7. **Report**: Show exit code and whether the run succeeded.
