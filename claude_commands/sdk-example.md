Build and run one of the XCENA SDK examples.

`$ARGUMENTS` is the example name (e.g., `sort`, `data_copy`, `vector`, `echo`, `memory_test`). Omit to list available examples.

## Steps

### 0. List available examples (if no argument given)
```bash
ls /sdk_release/example/
ls ~/example/ 2>/dev/null
```
Print the list and stop.

### 1. Locate the example
Check in order:
1. `~/example/$ARGUMENTS/` (local copy, may be pre-built)
2. `/sdk_release/example/$ARGUMENTS/`

```bash
EXAMPLE_DIR=""
[ -d ~/example/$ARGUMENTS ] && EXAMPLE_DIR=~/example/$ARGUMENTS
[ -z "$EXAMPLE_DIR" ] && [ -d /sdk_release/example/$ARGUMENTS ] && \
  EXAMPLE_DIR=/sdk_release/example/$ARGUMENTS
[ -z "$EXAMPLE_DIR" ] && echo "Example '$ARGUMENTS' not found" && exit 1
```

### 2. Build
```bash
cd $EXAMPLE_DIR
cmake -B build -DCMAKE_BUILD_TYPE=Release . 2>&1 | tail -5
cmake --build build -j"$(nproc)" 2>&1
```
On build failure, show the last 30 lines of output and stop.

### 3. Find the binary
```bash
BINARY=$(find $EXAMPLE_DIR/build -maxdepth 3 -type f -perm -u+x \
         ! -name "*.so" ! -name "*.a" | head -1)
echo "Binary: $BINARY"
```

### 4. Run with THP enabled
Build the THP-enable wrapper if needed:
```bash
[ -x /tmp/thp_enable ] || gcc -O2 -o /tmp/thp_enable - << 'EOF'
#include <sys/prctl.h>
#include <unistd.h>
int main(int c, char **v) {
    prctl(PR_SET_THP_DISABLE, 0, 0, 0, 0);
    if (c > 1) execv(v[1], v+1);
    return 1;
}
EOF
```

```bash
cd $EXAMPLE_DIR/build
/tmp/thp_enable $BINARY 2>&1
echo "Exit: $?"
```

### 5. Check for known issues
If the run fails:
```bash
sudo dmesg | grep -E "device_dax|dax_fault|alignment|SIGBUS" | tail -10
```
Suggest using `/debug-device` for deeper diagnosis.

### 6. Report
Show exit code and a one-line summary of what the example does and whether it passed.
