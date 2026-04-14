Build the CMake project in the current directory (or a specified subdirectory).

`$ARGUMENTS` (optional): subdirectory or build flags (e.g., `Release`, `Debug`, `~/example/sort`). Defaults to the current directory with `Release` build type.

## Steps

### 1. Locate the project root
- If `$ARGUMENTS` contains a path, `cd` to it.
- Verify `CMakeLists.txt` exists; if not, search parent directories up to 3 levels.
  ```bash
  ls CMakeLists.txt 2>/dev/null || ls ../CMakeLists.txt 2>/dev/null || ls ../../CMakeLists.txt 2>/dev/null
  ```

### 2. Determine build type
- Default: `Release`
- If `$ARGUMENTS` contains `Debug` or `debug`, use `Debug`.
- If `$ARGUMENTS` contains `RelWithDebInfo`, use `RelWithDebInfo`.

### 3. Configure
```bash
cmake -B build \
      -DCMAKE_BUILD_TYPE=<build_type> \
      -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
      .
```

### 4. Build
```bash
cmake --build build -j"$(nproc)" 2>&1 | tee /tmp/build_output.txt
BUILD_EXIT=${PIPESTATUS[0]}
```

### 5. Evaluate result

**On success** (exit 0):
- List generated binaries:
  ```bash
  find build -maxdepth 3 -type f \( -perm -u+x \) ! -name "*.so" ! -name "*.a" | sort
  ```
- Note `.mubin` files if pxcc was involved:
  ```bash
  find build -name "*.mubin" | sort
  ```

**On failure** (non-zero exit):
- Show the last 40 lines of build output.
- Identify error type:
  - `error: 'pxl/pxl.hpp' file not found` → SDK not on include path; check `CMAKE_PREFIX_PATH` or `PKG_CONFIG_PATH`
  - `undefined reference to pxl::` → link with `-lpxl`
  - `pxcc: command not found` → pxcc not in PATH; check `/sdk_release/tools/pxcc/`
  - `alignment` / `DAX` errors at runtime → use `/run-device` instead of running directly
- Suggest a targeted fix.

### 6. Report
Show a one-line summary: `Build SUCCEEDED` or `Build FAILED` with the binary path or error location.
