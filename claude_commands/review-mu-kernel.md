Review MU kernel code for correctness, performance, and compliance with XCENA constraints.

`$ARGUMENTS` is the path to the MU kernel source file or directory (e.g., `mu_kernel/mu_kernel.cpp`, or `.` to review all `.cpp` files under `mu_kernel/`).

## Review Criteria

### 1. Locate kernel files
```bash
# If $ARGUMENTS is a directory or '.':
find "$ARGUMENTS" -name "*.cpp" | sort

# Otherwise treat as a file path
```
Read each file in full.

### 2. Structural correctness

Check each kernel function for:

**a. MU_KERNEL_ADD registration**
Every function intended to be called from the host must have `MU_KERNEL_ADD(<name>)` at file scope. Missing registration = silent failure at runtime (kernel load succeeds but function is unreachable).

**b. Parameter count (≤ 9)**
Count parameters for each `MU_KERNEL_ADD`-registered function. Flag any with more than 9.

**c. Task-parallel indexing**
For pointer-based multi-task kernels, verify `mu::getTaskIdx()` is used to compute the correct offset:
```cpp
auto taskIdx = mu::getTaskIdx();
// data[taskIdx * size ... taskIdx * size + size - 1]
```
Missing task indexing = all tasks overwrite the same memory region.

**d. Required header**
```cpp
#include "mu/mu.hpp"
```
Must be present.

### 3. Memory safety

**a. Heap usage**
The kernel heap is limited to 3 MB. Flag:
- Large stack-allocated arrays (> a few KB)
- Dynamic allocations whose total could exceed 3 MB across concurrent tasks

**b. Stack usage**
Stack is limited to 64 KB. Flag deep call chains or large local variables.

**c. Out-of-bounds access**
Check loop bounds: `for (int i = 0; i < size; ++i)` with access `data[base + i]` — verify `base + size` cannot exceed the allocated region given `numTasks` and `chunkSize` from the host side.

### 4. Performance hints

- **Vectorization**: Does the inner loop operate on contiguous memory? Flag scatter/gather patterns.
- **Branch divergence**: Are there data-dependent branches inside the task loop? RISC-V cores are in-order; branches are cheap but note heavy divergence.
- **std::sort / std::algorithm**: Fully supported and often faster than hand-rolled loops for small sizes.
- **Unnecessary flushHostCache**: The kernel runs in-memory; `flushHostCache` is only needed on the host side.

### 5. Compliance checklist

| Check | Pass / Fail | Notes |
|---|---|---|
| `#include "mu/mu.hpp"` present | | |
| All host-callable functions have `MU_KERNEL_ADD` | | |
| Parameter count ≤ 9 | | |
| `mu::getTaskIdx()` used for task indexing | | |
| No stack arrays > 16 KB | | |
| No dynamic alloc exceeding 3 MB | | |
| Loop bounds are safe | | |

### 6. Summary

- List all findings with file:line references.
- Classify as **blocker** (will cause incorrect behavior or crash) or **suggestion** (performance/style).
- For blockers, provide the corrected code snippet.
