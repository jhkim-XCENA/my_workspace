# Plan: L7 Cost Model — Hardware-Measured Instruction Latencies

---

## 배경 및 진행 상황

### 프로젝트 개요
PR #33 (`feature/metis-cost-model-phase1`, repo: `xcena-dev/llvm-project-fork`)은 MX1 전용 LLVM 스케줄링 모델 `MetisModel`을 도입한다. CSV 파일(`phase1_instr.csv`, `phase1_model.csv`, `phase1_bypass.csv`)로 파라미터를 관리하고, `phase1_update.py`로 `RISCVSchedMetis.td`에 적용하는 파이프라인이다.

### 완료된 작업 (L1~L5)
1. **L1** (기준선): 시스템 LLVM, `RocketModel` 사용
2. **L3** (기본 CSV): MetisModel, placeholder 값 (RocketModel과 동일)
3. **L5** (수정된 CSV): MetisModel, 아키텍처 기반으로 수정한 값:
   - IMUL_LATENCY: 4→3, LDW/LDD_LATENCY: 4→3 (L1 cache hit 기준), FADD32: 2→4
4. **검증 완료**:
   - sort (7개 알고리즘), dotprod (8-way ILP) 벤치마크
   - L5 어셈블리 diff: `lw` 순서 변경, mul+add 인터리빙 개선 확인
   - xpti 프로파일링: dotprod L5가 L1 대비 IPC 0.8% 향상, std_dev -37.5%
5. **보고서**: `/llvm-project/verification_report.md` 작성 완료, PR #33에 push

### 현재 과제 (L7)
**목표**: MX1 하드웨어에서 실제 instruction latency를 직접 측정하여 `phase1_instr.csv`를 갱신하고, L7 cost model을 만들어 재벤치마킹

---

## L7 업데이트 대상 파라미터

| CSV 파라미터 | L5 latency | L5 release_at | L7 (측정값으로 대체) |
|------------|-----------|---------------|-------------------|
| IMUL_LATENCY | 3 | 1 | 측정 필요 |
| IMUL32_LATENCY | 3 | 1 | 측정 필요 |
| IDIV32_LATENCY | 34 | 34 | 측정 필요 |
| IDIV64_LATENCY | 33 | 33 | 측정 필요 |
| IREM32_LATENCY | 34 | 34 | 측정 필요 |
| IREM64_LATENCY | 33 | 33 | 측정 필요 |
| FMUL32_LATENCY | 5 | 5 | 측정 필요 |
| FMUL64_LATENCY | 7 | 7 | 측정 필요 |
| FDIV32_LATENCY | 20 | 20 | 측정 필요 |
| FDIV64_LATENCY | 20 | 20 | 측정 필요 |

---

## Step 1 — `/work/example/opbench/` 생성 (사이클 측정 + 워크로드 커널)

### 핵심 API 조사 결과

`/sdk_release/lib/mu_lib/` 서브모듈(`git submodule update --init lib/mu_lib`)을 분석한 결과:

| 메커니즘 | 구현 방식 | 소스 파일 |
|---------|----------|----------|
| `mu::getClockCycle()` | `cbusrd addr` (CBUS 메모리맵 레지스터 읽기) | `src/mu/clock/clock.cpp` |
| `mu::getExecutionCount()` | `csrget rd, 3` (CSR #3 = InstructionCount) | `src/mu/info/info.cpp` |
| SDK inline asm 스타일 | `asm volatile("instr %0, %0, %1" : "+r"(r) : "r"(b))` | `src/mu/intrinsic/intrinsic_common.hpp` |
| IR drop 패턴 | `asm volatile("addi a0, a1, 256")` — 의존성 체인 | `src/mu/test/ir_drop/detail/alu.cpp` |

**측정 전략**:
- **타이밍**: `mu::getClockCycle()` (CBUS 읽기 — 올바른 방법)
- **측정 대상 instruction**: `asm volatile`로 정확히 지정 (컴파일러가 다른 instruction으로 대체하거나 제거하는 것 방지)
- **검증**: `mu::getExecutionCount()`로 실제 실행된 instruction 수 확인 가능

### 1a. MU 커널: `mu_kernel/mu_opbench.cpp`

`ir_drop/alu.cpp`의 의존성 체인 패턴 + constraint 기반 asm (레지스터 이름 하드코딩보다 안전):

```cpp
#include "mu/clock/clock.hpp"
#include "mu/info/info.hpp"

// ──────────────────────────────────────────────────
// LATENCY 측정: 의존성 체인, 8×언롤, N 루프 반복
//   latency_cycles = raw_cycles / (N * 8)
//
// THROUGHPUT 측정: 8개 독립 체인, N 루프 반복
//   release_at_cycles = raw_cycles / (N * 8)
// ──────────────────────────────────────────────────

// --- ADD (보정 기준: 예상 lat=1, rel=1) ---
static uint64_t lat_add64(int N) {
    int64_t r = 1, b = 1;
    uint64_t t0 = mu::getClockCycle();
    for (int i = 0; i < N; i++)
        asm volatile(
            "add %0,%0,%1\n add %0,%0,%1\n add %0,%0,%1\n add %0,%0,%1\n"
            "add %0,%0,%1\n add %0,%0,%1\n add %0,%0,%1\n add %0,%0,%1"
            : "+r"(r) : "r"(b));
    uint64_t t1 = mu::getClockCycle();
    (void)r; return t1 - t0;
}
static uint64_t thr_add64(int N) {
    int64_t r0=1,r1=2,r2=3,r3=4,r4=5,r5=6,r6=7,r7=8, b=1;
    uint64_t t0 = mu::getClockCycle();
    for (int i = 0; i < N; i++)
        asm volatile(
            "add %0,%0,%8\n add %1,%1,%8\n add %2,%2,%8\n add %3,%3,%8\n"
            "add %4,%4,%8\n add %5,%5,%8\n add %6,%6,%8\n add %7,%7,%8"
            : "+r"(r0),"+r"(r1),"+r"(r2),"+r"(r3),"+r"(r4),"+r"(r5),"+r"(r6),"+r"(r7)
            : "r"(b));
    uint64_t t1 = mu::getClockCycle();
    (void)(r0+r1+r2+r3+r4+r5+r6+r7); return t1 - t0;
}

// --- MUL 64-bit ("mul rd, rs1, rs2") ---
static uint64_t lat_mul64(int N) {
    int64_t r = 1, b = 3;
    uint64_t t0 = mu::getClockCycle();
    for (int i = 0; i < N; i++)
        asm volatile(
            "mul %0,%0,%1\n mul %0,%0,%1\n mul %0,%0,%1\n mul %0,%0,%1\n"
            "mul %0,%0,%1\n mul %0,%0,%1\n mul %0,%0,%1\n mul %0,%0,%1"
            : "+r"(r) : "r"(b));
    uint64_t t1 = mu::getClockCycle();
    (void)r; return t1 - t0;
}
static uint64_t thr_mul64(int N) {
    int64_t r0=1,r1=2,r2=3,r3=4,r4=5,r5=6,r6=7,r7=8, b=3;
    uint64_t t0 = mu::getClockCycle();
    for (int i = 0; i < N; i++)
        asm volatile(
            "mul %0,%0,%8\n mul %1,%1,%8\n mul %2,%2,%8\n mul %3,%3,%8\n"
            "mul %4,%4,%8\n mul %5,%5,%8\n mul %6,%6,%8\n mul %7,%7,%8"
            : "+r"(r0),"+r"(r1),"+r"(r2),"+r"(r3),"+r"(r4),"+r"(r5),"+r"(r6),"+r"(r7)
            : "r"(b));
    uint64_t t1 = mu::getClockCycle();
    (void)(r0+r1+r2+r3+r4+r5+r6+r7); return t1 - t0;
}
// MULW → "mulw" mnemonic, "+r" constraint, 동일 패턴
// DIV/DIVW/REM/REMW → 동일 패턴, slow_N 사용
// FMUL.S/FDIV.S/FMUL.D/FDIV.D → "+f" constraint 사용
// 예시:
static uint64_t lat_fmul32(int N) {
    float r = 1.5f, b = 1.001f;
    uint64_t t0 = mu::getClockCycle();
    for (int i = 0; i < N; i++)
        asm volatile(
            "fmul.s %0,%0,%1\n fmul.s %0,%0,%1\n fmul.s %0,%0,%1\n fmul.s %0,%0,%1\n"
            "fmul.s %0,%0,%1\n fmul.s %0,%0,%1\n fmul.s %0,%0,%1\n fmul.s %0,%0,%1"
            : "+f"(r) : "f"(b));
    uint64_t t1 = mu::getClockCycle();
    (void)r; return t1 - t0;
}
```

**반복 횟수**:
- 빠른 ops (add, mul, fmul): `fast_N = 256` → 256×8 = 2048 ops
- 느린 ops (div, rem, fdiv): `slow_N = 32` → 32×8 = 256 ops

**커널 엔트리 포인트**:
```cpp
MU_KERNEL void opbench_kernel(uint64_t* results, int fast_N, int slow_N);
// results[0..1]:   lat/thr add64   (보정 기준)
// results[2..3]:   lat/thr mul64
// results[4..5]:   lat/thr mulw32
// results[6..7]:   lat/thr div64
// results[8..9]:   lat/thr divw32
// results[10..11]: lat/thr rem64
// results[12..13]: lat/thr remw32
// results[14..15]: lat/thr fmul32
// results[16..17]: lat/thr fmul64
// results[18..19]: lat/thr fdiv32
// results[20..21]: lat/thr fdiv64
MU_KERNEL_ADD(opbench_kernel)
```

### 1b. 워크로드 커널: `mu_kernel/mu_workloads.cpp`

L1/L5/L7 비교 벤치마크용 compute 커널 (다양한 크기):

```cpp
// bench_imul: N번 multiply-accumulate (8개 독립 누산기로 ILP 노출)
MU_KERNEL void bench_imul(long long* result, int N)

// bench_idiv: N번 divide-accumulate
MU_KERNEL void bench_idiv(long long* result, int N)

// bench_irem: N번 remainder-accumulate
MU_KERNEL void bench_irem(long long* result, int N)

// bench_fmul32/fdiv32: FP32 multiply/divide accumulate
// bench_fmul64/fdiv64: FP64 multiply/divide accumulate
```

### 1c. 호스트 드라이버: `opbench_host.cpp`

**Device 선택**: device 0 비정상 → **device 1 사용**. SDK 패턴(`test_device_utils.hpp`)을 따라 `XCENA_DEVICE_ID` env var 또는 `-d` CLI 옵션으로 지정:

```cpp
// 기본값: 1 (device 0 비정상)
int deviceId = 1;
const char* envDev = std::getenv("XCENA_DEVICE_ID");
if (envDev) deviceId = atoi(envDev);
// -d <id> 옵션이 있으면 override
```

```
사용법: ./opbench_host [-d <deviceId>] [-m measure|bench] [-n <taskCount>] [-s <opCount>]
  -d  device ID (기본값: 1, device 0 비정상)
  -m measure  : 사이클 측정 커널 실행, latency/release_at 표 출력
  -m bench    : 워크로드 커널 실행 (L1/L5/L7 비교용 타이밍)
```

측정 모드 출력 예시:
```
Op          N    RawCyc   Lat(cyc)  ThrRaw   Rel(cyc)
ADD-64      256   2048    1.00      2048     1.00
MUL-64      256   6144    3.00      2048     1.00
DIV-64       32  32768   32.00     32768    32.00
FMUL-32     256  10240    5.00      2048     1.00
...
```

### 1d. 빌드 파일

`build.sh`:
```bash
export MU_LLVM_PATH=${LLVM_PATH:-/usr/local/mu_library/mu_llvm/$XCENA_LLVM_VERSION/$MU_REVISION/}
```

`mu_kernel/CMakeLists.txt`: `-mcpu=metisx-d -O3`, 표준 MU 빌드 플래그.

참고 패턴: `/work/example/dotprod/build.sh`, `/work/example/dotprod/mu_kernel/CMakeLists.txt`

---

## Step 2 — opbench 빌드 및 측정 실행

```bash
cd /work/example/opbench
LLVM_PATH=/llvm-project/260414_cost_model ./build.sh   # L5 LLVM 사용 (HW 카운터에 무관)
./opbench_host -m measure -d 1   # device 0 비정상, device 1 사용
```

예상 측정 결과 (MX1 4-stage in-order, 1.1 GHz 기준):
- ADD: lat≈1, rel≈1
- MUL64: lat≈3~5, rel≈1 (파이프라인된 멀티플라이어)
- DIV64: lat≈20~40, rel≈20~40 (비파이프라인)
- FMUL32: lat≈4~6, rel≈1 또는 lat값 (HW에 따라 다름)
- FDIV32: lat≈15~25, rel≈15~25 (비파이프라인)

---

## Step 3 — `phase1_instr.csv` 업데이트 → L7

`/llvm-project/xcena/cost_model/phase1_instr.csv`에서 측정값으로 교체:
- 대상: IMUL, IMUL32, IDIV32, IDIV64, IREM32, IREM64, FMUL32, FMUL64, FDIV32, FDIV64
- 유지: LDW_LATENCY, LDD_LATENCY, FADD32/64 (이번 측정 제외)

적용:
```bash
cd /llvm-project
python3 xcena/cost_model/phase1_update.py --apply --verify
```

---

## Step 4 — LLVM 증분 빌드 (L7)

`.td` 파일만 변경됐으므로 전체 빌드 불필요:

```bash
cd /llvm-project/build
ninja LLVMRISCVCodeGen   # RISCV 코드젠만 재빌드

# 새 경로에 설치
cmake --install . --prefix /llvm-project/260415_l7_cost_model
# 또는 install prefix가 하드코딩되어 있으면:
# cmake -DCMAKE_INSTALL_PREFIX=/llvm-project/260415_l7_cost_model .
# ninja install
```

검증:
```bash
/llvm-project/260415_l7_cost_model/bin/llc --version   # XCENA LLVM 확인
```

---

## Step 5 — L7 LLVM로 워크로드 재빌드

```bash
# dotprod
cd /work/example/dotprod
./build.sh && cp build/mu_kernel/mu_kernel.mubin /tmp/mu_kernel_l1.mubin
LLVM_PATH=/llvm-project/260414_cost_model ./build.sh && cp build/mu_kernel/mu_kernel.mubin /tmp/mu_kernel_l5.mubin
LLVM_PATH=/llvm-project/260415_l7_cost_model ./build.sh && cp build/mu_kernel/mu_kernel.mubin /tmp/mu_kernel_l7.mubin

# opbench 워크로드 모드
cd /work/example/opbench
LLVM_PATH=/llvm-project/260415_l7_cost_model ./build.sh && cp build/mu_kernel/mu_kernel.mubin /tmp/opbench_kernel_l7.mubin
```

---

## Step 6 — 어셈블리 diff: L5 vs L7

```bash
OBJDUMP=/llvm-project/260415_l7_cost_model/bin/llvm-objdump
$OBJDUMP -d /tmp/mu_kernel_l5.mubin > /tmp/asm_l5.txt
$OBJDUMP -d /tmp/mu_kernel_l7.mubin > /tmp/asm_l7.txt
diff /tmp/asm_l5.txt /tmp/asm_l7.txt
```

분석 포인트: dotprod 내부 루프에서 mul+add 인터리빙 패턴 변화.

---

## Step 7 — 벤치마크: L1 vs L5 vs L7

**dotprod** (3 configs × 3 sizes):
```bash
for TAG in l1 l5 l7; do
    cp /tmp/mu_kernel_$TAG.mubin /work/example/dotprod/build/mu_kernel/mu_kernel.mubin
    for ARGS in "-d 1 -n 64 -s 1024" "-d 1 -n 256 -s 1024" "-d 1 -n 64 -s 4096"; do
        echo -n "$TAG $ARGS: "
        /work/example/dotprod/build/dotprod_with_ptr $ARGS
    done
done
```

**opbench 워크로드** (3 configs × 7 kernels):
- bench_imul, bench_idiv, bench_irem, bench_fmul32, bench_fdiv32, bench_fmul64, bench_fdiv64
- `-n 64 -s 1024`, `-n 64 -s 4096`

---

## Step 8 — `verification_report.md` L7 섹션 추가, commit/push

섹션 "9. L7 Cost Model — 하드웨어 측정 기반 latency" 추가:
1. opbench 측정 방법론 (사이클 카운터, inline asm)
2. 측정값 테이블 vs L5 추정값
3. 업데이트된 CSV 근거
4. 어셈블리 diff L5→L7 분석
5. 벤치마크 테이블: L1/L5/L7 × dotprod/opbench
6. 결론: 어떤 op에서 효과가 큰가

```bash
cd /llvm-project
git add xcena/cost_model/phase1_instr.csv verification_report.md
git commit -m "feat: add L7 cost model with hardware-measured instruction latencies"
git push origin feature/metis-cost-model-phase1
```

---

## 주요 파일 목록

### 새로 생성할 파일

| 파일 | 설명 |
|------|------|
| `/work/example/opbench/mu_kernel/mu_opbench.cpp` | 사이클 측정 커널 (inline asm) |
| `/work/example/opbench/mu_kernel/mu_workloads.cpp` | 워크로드 커널 (L1/L5/L7 비교) |
| `/work/example/opbench/opbench_host.cpp` | 호스트 드라이버 (measure/bench 모드) |
| `/work/example/opbench/mu_kernel/CMakeLists.txt` | MU 커널 빌드 |
| `/work/example/opbench/CMakeLists.txt` | ExternalProject 래퍼 |
| `/work/example/opbench/build.sh` | LLVM_PATH 오버라이드 포함 빌드 스크립트 |

### 수정할 파일

| 파일 | 수정 내용 |
|------|----------|
| `/llvm-project/xcena/cost_model/phase1_instr.csv` | 측정된 latency/release_at 값으로 10개 파라미터 업데이트 |
| `/llvm-project/llvm/lib/Target/RISCV/RISCVSchedMetis.td` | phase1_update.py가 자동 업데이트 |
| `/llvm-project/verification_report.md` | L7 섹션 추가 |

### 참조 파일 (수정 없음)

| 파일 | 용도 |
|------|------|
| `/usr/local/mu_library/mu/include/mu/clock/clock.hpp` | `mu::getClockCycle()` API |
| `/sdk_release/lib/mu_lib/mu/src/mu/intrinsic/intrinsic_common.hpp` | inline asm 패턴 참조 |
| `/sdk_release/lib/mu_lib/mu/src/mu/test/ir_drop/detail/alu.cpp` | 의존성 체인 패턴 참조 |
| `/work/example/dotprod/mu_kernel/mu_dotprod.cpp` | MU 커널 구조 패턴 |
| `/work/example/dotprod/dotprod_with_ptr.cpp` | 호스트 드라이버 패턴 |
| `/work/example/dotprod/build.sh` | 빌드 스크립트 패턴 |
| `/llvm-project/xcena/cost_model/phase1_update.py` | CSV→.td 적용 스크립트 |
| `/llvm-project/build/` | 증분 빌드 디렉토리 |

---

## 측정 수식

```
latency_cycles    = raw_cycles / (N × 8)   [의존성 체인, 8×언롤]
release_at_cycles = raw_cycles / (N × 8)   [8개 독립 체인, N 반복]

보정: ADD를 기준으로 측정 (예상 = 1)
  ADD 측정값이 1이 아니면 loop overhead를 보정
```

---

## MX1 아키텍처 참고 (측정값 해석 기준)

- RV64IMFD, 4-stage in-order, ISSUE_WIDTH=1, 1.1 GHz
- L1 D-cache: 4KB/MU (2KB heap + 2KB stack)
- L2: 256KB/cluster (32 MUs 공유), L3: 128MB 공유
- 멀티플라이어: 파이프라인 여부 미확인 → 측정으로 확인
- 디바이더: 비파이프라인 예상 (release_at = latency)
- FP 유닛: RV64FD 구현 세부 사항 미공개 → 측정으로 확인
