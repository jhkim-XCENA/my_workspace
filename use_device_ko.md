# Claude Code에서 DAX/CXL 디바이스 프로그램 실행하기

## 배경

Claude Code의 Bash 툴로 CXL 메모리(DAX 디바이스, 예: `/dev/dax0.0`)에 접근하는 프로그램을 실행하면, 같은 프로그램을 직접 셸에서 실행할 때는 정상 동작하지만 **Bus Error (SIGBUS, 종료 코드 135)** 가 발생합니다.

이 문서는 근본 원인, 전체 진단 과정, 그리고 해결책을 설명합니다.

---

## 증상

```
# Claude Code Bash 툴로 실행 → SIGBUS (exit 135)
$ cd ~/example/data_copy && ./data_copy

# 직접 셸에서 실행 → 성공
$ ./data_copy
```

dmesg 출력:
```
device_dax:dev_dax_huge_fault: data_copy: write (...) order:0
device_dax:__dev_dax_pte_fault: alignment (0x200000) > fault size (0x1000)
```

---

## 근본 원인

### 1. Claude Code가 `prctl`로 THP를 비활성화

Claude Code(Node.js 프로세스)는 내부적으로 다음을 호출합니다:
```c
prctl(PR_SET_THP_DISABLE, 1, ...)
```
이로 인해 자신의 메모리 디스크립터(`mm_struct`)에 `MMF_DISABLE_THP` 비트가 세팅됩니다.

### 2. fork + exec을 거쳐도 플래그가 상속됨

Claude Code가 서브프로세스(명령을 실행할 셸)를 생성할 때:

1. **`fork()`** — 자식 프로세스가 부모의 mm을 복사 → `MMF_DISABLE_THP = 1` 상속
2. **`exec()`** — `mm_alloc()`으로 새 `mm_struct`를 할당하지만, `mm_init()`이 `MMF_INIT_MASK`에 해당하는 플래그를 현재(exec 직전) mm에서 새 mm으로 복사함

커널 소스(`include/linux/sched/coredump.h`):
```c
#define MMF_INIT_MASK  (MMF_DUMPABLE_MASK | MMF_DUMP_FILTER_MASK | \
                        MMF_DISABLE_THP_MASK | MMF_HAS_MDWE_MASK | ...)
```

`MMF_DISABLE_THP`가 `MMF_INIT_MASK`에 포함되어 있어 **exec 이후에도 THP 비활성화 플래그가 유지**됩니다.

즉, Claude Code가 실행하는 모든 프로그램은 셸 파이프라인의 exec 횟수와 관계없이 THP가 비활성화된 상태로 동작합니다.

확인 방법:
```bash
# Claude Code의 셸 안에서
cat /proc/self/status | grep THP
# THP_enabled:  0    ← THP 비활성화됨

# 사용자의 직접 셸에서
cat /proc/self/status | grep THP
# THP_enabled:  1    ← THP 활성화됨
```

### 3. DAX 디바이스에서 THP가 필요한 이유

CXL DAX 디바이스(`/dev/dax*.0`)는 2MB 정렬을 요구합니다(`dax_region/align = 2097152`). device-dax 드라이버(`drivers/dax/device.c`)는 페이지 폴트를 PMD order (order 9, 2MB) 또는 PUD order (order 18, 1GB) 수준에서 처리해야 합니다:

```c
// __dev_dax_pte_fault — order == 0일 때 호출됨
if (dev_dax->align > PAGE_SIZE) {
    dev_dbg(..., "alignment (%#x) > fault size (%#x)\n", ...);
    return VM_FAULT_SIGBUS;   // ← SIGBUS 발생
}
```

커널은 `thp_vma_allowable_order()`가 non-zero를 반환할 때만 PMD/PUD 수준의 폴트를 시도합니다. 이 함수는 `vma_thp_disabled()`를 호출하는데, `MMF_DISABLE_THP`가 세팅되어 있으면 `true`를 반환합니다:

```c
static inline bool vma_thp_disabled(struct vm_area_struct *vma,
                                     unsigned long vm_flags)
{
    return (vm_flags & VM_NOHUGEPAGE) ||
           test_bit(MMF_DISABLE_THP, &vma->vm_mm->flags);  // ← 여기서 true
}
```

**THP 비활성화 시 폴트 경로 (ftrace로 확인)**:
```
__handle_mm_fault
  └─ thp_vma_allowable_order(PMD_ORDER) == 0  ← THP 비활성화로 스킵
  └─ handle_pte_fault
       └─ __do_fault
            └─ dev_dax_fault          (order 0, 4KB)
                 └─ dev_dax_huge_fault (order 0)
                      └─ __dev_dax_pte_fault
                           └─ VM_FAULT_SIGBUS  ← 2MB 정렬 ≠ 4KB 폴트
```

**THP 활성화 시 (사용자 직접 실행, 또는 수정 후)**:
```
__handle_mm_fault
  └─ thp_vma_allowable_order(PUD_ORDER) → non-zero
  └─ create_huge_pud → dev_dax_huge_fault (order 18, 1GB)
       └─ __dev_dax_pud_fault → 성공
```

---

## 해결 방법

### 방법 1: prctl 래퍼 프로그램 (즉시 적용, SDK 수정 불필요)

THP를 다시 활성화한 후 대상 프로그램을 `exec`하는 C 헬퍼 프로그램:

```c
// thp_enable.c
#include <stdio.h>
#include <sys/prctl.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    prctl(PR_SET_THP_DISABLE, 0, 0, 0, 0);  // THP 재활성화
    if (argc > 1)
        execv(argv[1], argv + 1);
    return 1;
}
```

```bash
gcc -o ~/thp_enable thp_enable.c
~/thp_enable ~/example/data_copy/data_copy   # Claude Code에서도 정상 동작
```

### 방법 2: SDK / 애플리케이션에서 수정 (권장)

프로그램 시작 부분(또는 SDK의 디바이스 초기화 경로)에서 DAX `mmap` 이전에 다음을 추가:

```c
#include <sys/prctl.h>

// main() 또는 SDK 초기화 함수 안에서:
prctl(PR_SET_THP_DISABLE, 0, 0, 0, 0);
```

실행 환경에 의존하지 않고 프로그램 자체적으로 처리하므로 가장 깔끔한 해결책입니다.

---

## 동작 확인

수정 후 dmesg에서 order:0 대신 **order:18** (1GB 휴지페이지) 또는 **order:9** (2MB)가 출력되어야 합니다:

```
device_dax:dev_dax_huge_fault: data_copy: write (...) order:18
```

그리고 프로그램이 exit code 0으로 정상 종료됩니다.

---

## 진단 과정 요약

1. **초기 증상**: Claude Code Bash 툴로 실행 시 SIGBUS, 직접 실행 시 성공
2. **환경 변수/셸 차이 확인**: `bash -c`, `bash --login -c`, `env -i`, `setsid` 등 모든 방법 시도 → 모두 SIGBUS → 환경 변수가 원인이 아님
3. **커널 폴트 경로 분석**: dmesg에서 order:0만 관찰, ftrace로 `handle_pte_fault`로 직행 확인
4. **커널 소스 분석**: `thp_vma_allowable_order` → `vma_thp_disabled` → `MMF_DISABLE_THP` 연결 발견
5. **원인 특정**: `prctl(PR_GET_THP_DISABLE)` 호출 → Claude Code 서브프로세스에서 1(비활성) 반환
6. **검증**: `prctl(PR_SET_THP_DISABLE, 0)` 호출 후 실행 → 성공, order:18 fault 확인

---

## 환경 정보

| 항목 | 내용 |
|---|---|
| 커널 | Linux 6.8.0-88-generic (Ubuntu) |
| DAX 디바이스 | `/dev/dax0.0`, `/dev/dax12.0`, `/dev/dax13.0` |
| DAX 정렬 | 2 MB (`dax_region/align = 2097152`) |
| CXL 리전 크기 | 디바이스당 약 233 GB |
| Claude Code | Node.js 프로세스로 동작 |

## 관련 커널 코드 위치

- `mm/memory.c` — `__handle_mm_fault`: `thp_vma_allowable_order`로 PUD/PMD 휴지 폴트 시도 결정
- `mm/huge_memory.c` — `__thp_vma_allowable_orders`: `vma_thp_disabled` 가 true이면 0 반환
- `include/linux/sched/coredump.h` — `MMF_INIT_MASK`에 `MMF_DISABLE_THP_MASK` 포함 → exec 이후에도 플래그 유지
- `drivers/dax/device.c` — `__dev_dax_pte_fault`: `align > PAGE_SIZE`이면 `VM_FAULT_SIGBUS` 반환
