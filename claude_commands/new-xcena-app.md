Scaffold a new XCENA SDK application with host code and MU kernel boilerplate.

`$ARGUMENTS` is the application name (e.g., `my_filter`). The project is created under `~/example/<name>/`.

## Steps

### 1. Parse and validate
- Application name: first token of `$ARGUMENTS`
- Destination: `~/example/<name>/`
- If the directory already exists, warn the user and stop.

### 2. Create directory structure
```
~/example/<name>/
├── CMakeLists.txt
├── build.sh
├── main.cpp          ← host application
└── mu_kernel/
    └── mu_kernel.cpp ← MU compute kernel
```

### 3. Write `mu_kernel/mu_kernel.cpp`

```cpp
#include "mu/mu.hpp"

// TODO: implement your compute kernel here.
// Constraints:
//   - max 9 parameters per host-callable function
//   - heap: 3 MB, stack: 64 KB
//   - use mu::getTaskIdx() for task-parallel indexing

void process(int* data, int size)
{
    auto taskIdx = mu::getTaskIdx();
    auto base    = taskIdx * size;

    for (int i = 0; i < size; ++i)
        data[base + i] = data[base + i];  // identity — replace with real logic
}
MU_KERNEL_ADD(process)
```

### 4. Write `main.cpp`

```cpp
#include <cstdio>
#include <cstring>
#include <sys/prctl.h>       // THP fix for Claude Code environment
#include "pxl/pxl.hpp"

int main(int argc, char** argv)
{
    // Re-enable THP so DAX page faults succeed (Claude Code disables it).
    prctl(PR_SET_THP_DISABLE, 0, 0, 0, 0);

    int deviceId  = 0;
    int numTasks  = 4;
    int chunkSize = 64;

    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "-d") && i + 1 < argc) deviceId  = atoi(argv[++i]);
        if (!strcmp(argv[i], "-n") && i + 1 < argc) numTasks  = atoi(argv[++i]);
        if (!strcmp(argv[i], "-s") && i + 1 < argc) chunkSize = atoi(argv[++i]);
    }

    printf("Device %d | tasks=%d chunk=%d\n", deviceId, numTasks, chunkSize);

    auto ctx = pxl::runtime::createContext(deviceId);
    if (!ctx) { fprintf(stderr, "Failed to create context\n"); return 1; }

    size_t totalBytes = (size_t)numTasks * chunkSize * sizeof(int);
    auto data = reinterpret_cast<int*>(ctx->memAlloc(totalBytes));
    if (!data) { fprintf(stderr, "memAlloc failed\n"); return 1; }

    // Initialize input
    for (int i = 0; i < numTasks * chunkSize; ++i) data[i] = i;
    pxl::flushHostCache(data, totalBytes);

    // Load kernel
    auto job = ctx->createJob();
    if (job->load("mu_kernel/mu_kernel.mubin") != pxl::PxlResult::Success) {
        fprintf(stderr, "Kernel load failed\n"); return 1;
    }

    // Execute
    auto executor = job->buildMap(numTasks);
    if (executor->execute(data, chunkSize) != pxl::PxlResult::Success) {
        fprintf(stderr, "Execute failed\n"); return 1;
    }
    executor->synchronize();

    printf("Done. data[0]=%d data[last]=%d\n", data[0], data[numTasks * chunkSize - 1]);

    ctx->memFree(data);
    return 0;
}
```

### 5. Write `CMakeLists.txt`

Use the SDK's standard `add_xcena_app` pattern (mirror `~/example/data_copy/CMakeLists.txt` if it exists; otherwise write a minimal version that links `pxl`).

Read `~/example/data_copy/CMakeLists.txt` as the canonical reference:
```bash
cat ~/example/data_copy/CMakeLists.txt
```

Then adapt it for `<name>`, replacing `data_copy` with the new app name.

### 6. Write `build.sh`

```bash
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
cmake -B build -DCMAKE_BUILD_TYPE=Release .
cmake --build build -j"$(nproc)"
echo "Built: ./build/<name>"
```

Make it executable: `chmod +x build.sh`

### 7. Remind the user

Print a summary:
```
Created ~/example/<name>/
  mu_kernel/mu_kernel.cpp  — edit your MU kernel here
  main.cpp                 — edit your host application here
  CMakeLists.txt
  build.sh

Next steps:
  1. Edit mu_kernel/mu_kernel.cpp  (pxcc compiles MU → .mubin)
  2. Edit main.cpp as needed
  3. Run: cd ~/example/<name> && ./build.sh
  4. Run: /run-device ./build/<name>
```
