# XPTI 프로파일러 사용 매뉴얼

본 문서는 XPTI(XCENA Performance Telemetry Interface)를 **프로파일러로서 사용하는 입장**에서 정리한 매뉴얼이다. 내부 구현은 다루지 않고, 애플리케이션 개발자가 자기 코드의 성능을 측정·분석하기 위해 필요한 사용법과, 수집된 데이터에서 읽어낼 수 있는 정보에 초점을 맞춘다.

> 이 매뉴얼의 모든 예시 출력은 실제 XCENA 디바이스에서 `sort_with_ptr` 예제를 돌려 얻은 값이다. 수치는 환경마다 달라진다.

---

## 목차

1. [XPTI란](#1-xpti란)
2. [시작하기 — 세 가지 진입 경로](#2-시작하기--세-가지-진입-경로)
3. [Hello, XPTI — 5분 실습](#3-hello-xpti--5분-실습)
4. [세션 모델 — Per-Map vs Process](#4-세션-모델--per-map-vs-process)
5. [`ProfileConfig` 상세](#5-profileconfig-상세)
6. [데이터 조회 API](#6-데이터-조회-api-프로그램-내부에서)
7. [사용자 정의 트레이스 스코프](#7-사용자-정의-트레이스-스코프)
8. [출력 포맷과 저장 구조](#8-출력-포맷과-저장-구조)
9. [xtop로 분석하기 — 전체 레퍼런스](#9-xtop로-분석하기--전체-레퍼런스)
10. [프로파일링으로 알 수 있는 것](#10-프로파일링으로-알-수-있는-것)
11. [원시 CSV 컬럼 레퍼런스](#11-원시-csv-컬럼-레퍼런스)
12. [증상→확인 포인트 매핑](#12-증상확인-포인트-매핑)
13. [오버헤드와 주의사항](#13-오버헤드와-주의사항)
14. [Python에서 결과 분석](#14-python에서-결과-분석-오프라인)
15. [Claude Code/DAX 환경에서 실행 시](#15-claude-codedax-환경에서-실행-시)
16. [문제 해결](#16-문제-해결)
17. [빠른 치트시트](#17-빠른-치트시트)
18. [참고 경로](#18-참고-경로)

---

## 1. XPTI란

- XCENA SDK에 포함된 프로파일링/텔레메트리 라이브러리.
- `libpxl`에 **PUBLIC**으로 링크되어 있어 사용자가 직접 호출 가능.
- 수집 대상:
  - **Host 측**: PXL API 진입/종료, `TaskDispatch/TaskComplete`, `MemCopy`, `MemAlloc/Free`, `StreamWait`, `MapStatusChange`, 사용자 정의 스코프.
  - **Device 측**: 커널 `Launch/Terminate`, Sub/Cluster/MU/Thread별 실행 위치, MU probe 이벤트.
  - **하드웨어 카운터(샘플링)**: L1 / L2 / L3 / MTC / PCU / MU / Gaia.
- 결과물: `.xpti`(SQLite) · `.csv`(원시/통계) · `.xprof`(직렬화 바이너리) → **xtop** 도구로 Perfetto 타임라인 시각화 가능.

### 1.1 아키텍처 한눈에 보기

```
 ┌────────────────┐   enable       ┌─────────────────────┐
 │ Application    │────────────────▶│ libpxl (Map/Job/..) │
 │ (C++ / Python) │                 └──────────┬──────────┘
 └────────────────┘                            │ 내부 호출
                                               ▼
                                     ┌───────────────────┐
                                     │ libxpti (PUBLIC)  │◀── 환경변수
                                     │  - session mgr    │    XPTI_ENABLE 등
                                     │  - probes         │
                                     │  - exporters      │
                                     └────────┬──────────┘
                                              ▼
                  ┌────────────┬──────────────┬──────────────┐
                  ▼            ▼              ▼              ▼
               .csv         .xpti          .xprof     in-memory API
              (원시/통계)  (SQLite)      (Python용)   getSessionData<Key>

                  ▼
              xtop / xprofiler
                  ├─ map   : 요약
                  ├─ task  : 태스크 상세
                  ├─ convert: .perfetto-trace
                  └─ open  : Perfetto UI
```

---

## 2. 시작하기 — 세 가지 진입 경로

XPTI는 동일한 세션 메커니즘을 세 가지 방식으로 사용한다. **대부분의 경우 방법 A로 충분**하다.

### 방법 A. `xtop run`으로 외부에서 감싸기 (가장 간단)

애플리케이션 코드 수정 없이 프로파일링이 가능하다.

```bash
sudo xtop run -- ./my_application [args...]
# → ./xtop_profile/profile_YYYYMMDD_HHMMSS.xpti 생성

sudo xtop run -o ./my_profile --perfetto -- ./my_application
# → .xpti + .perfetto-trace 동시 생성
```

내부적으로 `XPTI_ENABLE=1` 환경변수를 세팅하므로, PXL의 `Map` 생성자가 자동으로 프로파일링을 켠다. 이 경우 코드에 `enableProfiling()` 호출이 있어도 **무시**되고 xtop의 설정(`xtop_config.yaml`)이 우선한다.

> `xtop view`·`xtop run`은 `sudo` 필요. 분석 명령(`map`/`task`/`convert`/`open`)은 루트 권한 불필요.

### 방법 B. 환경변수로만 제어 (코드 수정 없음)

셸에서 직접 환경변수를 지정해도 동일한 자동 활성화가 동작한다.

| 환경변수 | 의미 | 예시 |
|---|---|---|
| `XPTI_ENABLE` | `1`이면 Map 생성 시 자동 프로파일링 | `1` |
| `XPTI_OUTPUT_PATH` | 결과 파일 저장 디렉토리 | `./out` |
| `XPTI_OUTPUT_FORMAT` | `csv` / `xpti` / `both` | `xpti` |
| `XPTI_PROCESS_PROFILE` | `1`이면 프로세스 단위 단일 세션 모드 | `1` |

```bash
XPTI_ENABLE=1 XPTI_OUTPUT_PATH=./out XPTI_OUTPUT_FORMAT=xpti ./my_application
```

세션별로 파일명은 `session_<mapId>_dev<deviceId>.xpti` 형식으로 생성된다. 예: `session_1_dev1.xpti`, `session_2_dev1.xpti` (한 프로세스에서 Map 2개를 실행한 경우).

### 방법 C. 프로그램 API로 세밀 제어 (C++)

특정 `Map`만 프로파일링하거나, 조건부로 on/off 하거나, 결과를 프로그램 내에서 직접 파싱할 때 사용한다.

```cpp
#include <pxl/pxl.hpp>

auto ctx = pxl::runtime::createContext(deviceId);
auto map = job->buildMap(func, taskCount);

xpti::ProfileConfig config{};
config.mode = xpti::ProfileMode::HostAndDevice;   // 기본
config.hostSamplingRate   = 0;   // 0 = 1000 ms 기본
config.deviceSamplingRate = 0;   // 0 = 1 ms 기본
// 비워 두면 9개 프로브 전체 활성화
config.enabledProbeTypes = { xpti::ProbeType::L1,
                             xpti::ProbeType::L3 };

map->enableProfiling(config);
map->setInput(data);
map->setOutput(data);
map->execute(data, sortSize);
map->synchronize();

map->exportProfilingCsv("./out");                       // CSV
map->exportProfiling("./out", xpti::ExportFormat::Both); // CSV+Xpti
```

참고: `lib/pxl/include/pxl/runtime/map.hpp:457`(`enableProfiling`), `:503`(`exportProfiling`), `:510`(`exportProfilingCsv`).

---

## 3. Hello, XPTI — 5분 실습

`sort_with_ptr` 예제를 대상으로 환경변수 방식을 그대로 재현해 본다.

```bash
mkdir -p /tmp/xpti_demo
XPTI_ENABLE=1 \
XPTI_OUTPUT_PATH=/tmp/xpti_demo \
XPTI_OUTPUT_FORMAT=xpti \
  ./sort_with_ptr
```

완료 후 파일 확인:

```bash
ls /tmp/xpti_demo/
# session_1_dev1.xpti   session_2_dev1.xpti
```

Map 단위 요약:

```bash
python3 -m xtop map /tmp/xpti_demo/session_1_dev1.xpti
```

실측 출력(일부 발췌):

```
[Hardware]
  Subs: 24   Clusters/Sub: 4   MUs/Cluster: 8   Threads/MU: 4
  Total threads    : 3,072
  MU frequency     : 1100 MHz

[Duration - Host]
  Wall time        : 6.76 ms
  Task count       : 32
  avg/median/min/max : 2.63 / 2.83 / 0.48 / 4.42 ms

[Duration - Device]
  Task count       : 3,360
  avg              : 22.36 us
  std_dev          : 1.00 us

[Overhead]
  Map 1 (execute → synchronize)
    host total       :    8.58 ms
      HostInit       :   66.00 us  (  0.8%)
      DeviceInit     :  692.00 us  (  8.1%)
      Request        :    4.14 ms  ( 48.3%)
      Waiting        :    3.10 ms  ( 36.1%)
      DeviceFinalize :   88.00 us  (  1.0%)
      HostFinalize   :  489.00 us  (  5.7%)

[Cache]
  L1 hit rate      : 98.0% (r:97.8% w:98.1%)
  L3 hit rate      : 99.6%

[Skew]
  balance_score    : 0.65 (Cluster0 75% / Cluster1 25%)
```

- 커널 자체는 22 µs 수준으로 매우 빠르고 std_dev도 1 µs로 균일.
- 대신 **Request 48% + Waiting 36%**로 호스트↔디바이스 통신이 병목.
- Cluster 단위로는 75/25로 쏠려 있어 워크로드 분배에 여지가 있음.

개별 태스크 파고들기:

```bash
python3 -m xtop task /tmp/xpti_demo/session_1_dev1.xpti --sort active --limit 5
python3 -m xtop task /tmp/xpti_demo/session_1_dev1.xpti 0
```

Perfetto 타임라인:

```bash
python3 -m xtop convert /tmp/xpti_demo/session_1_dev1.xpti
# → /tmp/xpti_demo/session_1_dev1.xpti.perfetto-trace
# 브라우저에서 https://ui.perfetto.dev 에 업로드
```

이 섹션에 나온 명령만으로 "실행 → 파일 생성 → 요약 → 태스크 → 타임라인"의 전체 플로우를 완주할 수 있다.

---

## 4. 세션 모델 — Per-Map vs Process

XPTI는 세션 단위로 데이터를 관리한다. 세션은 `sessionId`로 식별되며, PXL 경유 시 `map->id()`가 곧 `sessionId`다.

### 4.1 Per-Map 세션 (기본)

- 각 `Map`이 **독립 세션**을 갖는다.
- `map->synchronize()` 시점에 해당 세션이 종료되고 파일로 내보내진다.
- 장점: 여러 Map을 독립적으로 비교 가능. 병렬 Map도 별도 세션으로 관리됨.
- 파일명: `session_<mapId>_dev<deviceId>.xpti`

사용 예 (`tests/profile_test/pxl_profile_api/test_multi_map_profile.cpp`):

```cpp
auto map1 = job->buildMap(func, testCount);
auto map2 = job->buildMap(func, testCount);
map1->enableProfiling(config);
map2->enableProfiling(config);

std::thread t1([&]{ map1->execute(d1, n); map1->synchronize(); });
std::thread t2([&]{ map2->execute(d2, n); map2->synchronize(); });
t1.join(); t2.join();

map1->exportProfilingCsv(outDir);  // map1 전용 CSV
map2->exportProfilingCsv(outDir);  // map2 전용 CSV
```

### 4.2 Process 세션

- `XPTI_PROCESS_PROFILE=1`로 활성화. 프로세스 전체가 **하나의 세션**으로 묶인다.
- 여러 Map의 실행이 하나의 타임라인으로 이어 붙여져, 애플리케이션 end-to-end 흐름 분석에 적합.
- 데이터는 `atexit` 훅에서 내보내진다(프로세스 종료 시).
- 프로그래매틱 API: `xpti::startProcessSession(cfg, deviceId)` / `xpti::endProcessSession()`.
- 디바이스 폴링 일시중지/재개: `xpti::pauseDevicePolling(sid)` / `xpti::resumeDevicePolling(sid)` — 측정 구간을 좁히고 싶을 때.

```bash
XPTI_ENABLE=1 XPTI_PROCESS_PROFILE=1 \
XPTI_OUTPUT_PATH=./out XPTI_OUTPUT_FORMAT=xpti \
  ./my_application
```

### 4.3 선택 기준

| 상황 | 추천 모드 |
|---|---|
| 특정 Map만 집중 분석 | Per-Map |
| 병렬 Map의 독립성 확인 | Per-Map |
| 앱 전체 end-to-end 흐름 | Process |
| 다수 Map 간의 갭(유휴 시간) 분석 | Process |

---

## 5. `ProfileConfig` 상세

| 필드 | 기본값 | 의미 |
|---|---|---|
| `mode` | `HostAndDevice` | `HostOnly` / `DeviceOnly` / `HostAndDevice` |
| `hostSamplingRate` | `0` (= 1000 ms) | Host 샘플링 주기(ms) |
| `deviceSamplingRate` | `0` (= 1 ms) | Device 샘플링 주기(ms) |
| `enabledProbeTypes` | `{}` (= 전체) | 켤 프로브 집합 |
| `enabledDebugTypes` | `{}` (= 없음) | 디버그 로깅 집합 |
| `csvAppendTimestamp` | `true` | CSV 파일명에 타임스탬프 부가 |

### 5.1 프로브 종류 (`xpti::ProbeType`)

| 프로브 | 수집 내용 | 읽어낼 수 있는 것 |
|---|---|---|
| `Mu` | MU 실행 카운터(PC, exec count, COP 요청·응답) | 파이프라인 활용도 |
| `L1` | w_hit/miss, r_hit/miss, bypass, CPU cmd, L2 mwr/mrd | L1 캐시 지역성 |
| `L2` | trat/rrat/wrat/srat hit/miss, phy_cnt, bypass | L2 지역성·변환(TRAT) |
| `L3` | prat/vrat/wrat/rrat/srat hit/miss, araddr/awaddr | L3 지역성·실제 DDR 주소 |
| `MTC` | mrat hit/miss | MeTa Cache 효율 |
| `PCU` | CHI 계층 카운터(Req/Rwd/NDR/DRS 등 40+종) | 메모리 프로토콜 병목 |
| `Gaia` | smcPage/smcTlb hit/miss, ssdRead/Write, eviction | SSD 매핑 레이어 효율 |
| `HostEvent` | Host 함수 enter/exit | 호스트 타임라인·오버헤드 |
| `DeviceEvent` | 커널 Launch/Terminate, MU probe | 디바이스 타임라인 |

> **Perfetto 변환 시 필수**: `HostEvent`, `DeviceEvent`. 둘 중 하나라도 빠지면 타임라인에 해당 트랙이 비어있다.
> **오버헤드 감소**: 필요 없는 프로브는 제외. `xtop_config.yaml` 기본값은 `["L1","L2","L3","HostEvent","DeviceEvent"]`로 `Mu/MTC/PCU/Gaia`는 기본 비활성.

### 5.2 디버그 종류 (`xpti::DebugType`)

| 디버그 타입 | 용도 |
|---|---|
| `ProfileInfo` | 하드웨어 토폴로지·주파수 로깅 |
| `Core` | Core probe 샘플 전체 덤프 |
| `Mu` | MU probe 샘플 전체 덤프 |

문제 재현 시에만 활성. 상시 활성은 비용이 크다.

### 5.3 `xtop_config.yaml`

`xtop` 명령은 `./xtop_config.yaml`(CWD) / `$XTOP_CONFIG` / `--config` 경로에서 설정을 읽는다. CLI 인자가 항상 우선.

```yaml
mode: "HostAndDevice"
hostSamplingRate: 0
deviceSamplingRate: 0
enabledProbeTypes: ["L1","L2","L3","HostEvent","DeviceEvent"]
enabledDebugTypes: []
csvAppendTimestamp: true
device: 0
view_csv: false
csv_path: null
perfetto: true        # run 모드에서 .perfetto-trace 자동 생성
perfetto_path: null
```

---

## 6. 데이터 조회 API (프로그램 내부에서)

수집된 데이터를 **파일 없이 프로그램 메모리에서 직접 읽을 수 있다**. `QueryKey`로 어떤 데이터를 볼지 지정한다.

### 6.1 QueryKey 목록

| QueryKey | 반환 타입 | 용도 |
|---|---|---|
| `EventsHost` | `std::vector<HostEvent>` | 호스트 타임라인 |
| `EventsDevice` | `std::vector<DeviceEvent>` | 디바이스 타임라인 |
| `MetricsRaw{L1,L2,L3,MTC,MU,PCU,Gaia}` | `std::vector<*RawData>` | 원시 샘플 |
| `MetricsStats{L1,L2,L3,MTC,MU,PCU,Gaia}` | `stats::*Stats` | 집계값(global/perSub/perCluster) |
| `DeviceInfo` | `DeviceInfo` | 캐시라인·주파수 |

### 6.2 타입 안전한 조회

`Map::getProfilingData<Key>()`는 키에 따라 타입이 자동 추론된다.

```cpp
// L1 원시 샘플 전체
auto l1 = map->getProfilingData<xpti::QueryKey::MetricsRawL1>();
for (const auto& s : l1) {
    // s.subId, s.cluster, s.mu
    // s.w_hit, s.w_miss, s.r_hit, s.r_miss
    // s.hostTimestampUs, s.coreTimestamp
}
l1.exportCsv("l1_raw.csv");

// L1 집계: stats::L1Stats {global, perSub, perCluster}
auto l1s = map->getProfilingData<xpti::QueryKey::MetricsStatsL1>();
double globalHit = l1s.global.cacheHitStats.getHitRatio();
for (auto& [subId, e] : l1s.perSub) {
    printf("sub%u hit=%.2f%%\n",
           subId, e.cacheHitStats.getHitRatio() * 100.0);
}
```

### 6.3 필터링 (`QueryFilter`)

특정 Sub/Cluster/MU/Thread/DDR-Sub/L3-index만 추릴 수 있다. 비어 있는 필드는 "전체"를 의미한다.

```cpp
xpti::QueryFilter f;
f.subIds   = {0, 1};
f.clusters = {0};
f.mus      = {2, 3};
f.threads  = {0};            // EventsDevice에 유효
f.ddrSubs  = {};             // L3/MTC에 유효
f.l3Indices= {};

auto events = map->getProfilingData<xpti::QueryKey::EventsDevice>(f);

// 간편 생성자
auto f2 = xpti::QueryFilter::BySub(0);
auto f3 = xpti::QueryFilter::BySubs({0, 1, 2});
```

### 6.4 증분 조회 (실시간 스트리밍)

긴 실행을 주기적으로 스냅샷하려면 `getSessionDataDelta<Key>()`를 쓴다.

```cpp
uint64_t cursor = 0;
while (running) {
    auto d = xpti::getSessionDataDelta<xpti::QueryKey::EventsDevice>(
                 map->id(), cursor);
    for (const auto& e : d) { /* ... */ }
    std::this_thread::sleep_for(std::chrono::seconds(1));
}
```

### 6.5 세션 직접 제어 (Map 바깥)

`xpti::startProfileSession(cfg, deviceId, sessionId=0)` / `xpti::endProfileSession()`으로 Map 외부(예: CPU 전용 코드)에서도 세션을 열 수 있다. `sessionId=0`이면 자동 생성.

---

## 7. 사용자 정의 트레이스 스코프

자기 코드의 임의 구간을 타임라인에 올리고 싶을 때는 매크로를 사용한다.

### 7.1 RAII 스코프

```cpp
#include <xpti/xpti.hpp>

void preprocess() {
    XPTI_TRACE_FUNCTION();              // 함수명으로 scope
    // ...
}

void step() {
    XPTI_TRACE_SCOPE("bucket_sort");    // 이름 있는 scope
    // RAII로 자동 Exit
}
```

### 7.2 비-RAII (비동기 구간)

```cpp
XPTI_TRACE_BEGIN("async_prepare");
kickoffAsync();
// ... 다른 스레드에서 완료 콜백 내부 ...
XPTI_TRACE_END("async_prepare");
```

### 7.3 PXL 내부용 매크로 (사용자는 보통 필요 없음)

`XPTI_PUBLIC_API_SCOPE`, `XPTI_TASK_DISPATCH/COMPLETE`, `XPTI_MEM_COPY_BEGIN/END`, `XPTI_STREAM_WAIT_BEGIN/END`, `XPTI_MAP_STATUS_CHANGE`, `XPTI_MEM_ALLOC/FREE` 등은 PXL 라이브러리 내부에서 이미 삽입되어 있다.

### 7.4 컴파일 타임 완전 제거

릴리즈 빌드에서 트레이싱을 완전히 배제하려면 `-DXPTI_DISABLE_TRACING`. 모든 매크로가 `(void)0`으로 치환된다.

---

## 8. 출력 포맷과 저장 구조

| 포맷 | 내용 | 사용처 |
|---|---|---|
| `.csv` | 원시 레코드 + 집계 통계 | 스프레드시트·스크립트 분석 |
| `.xpti` | SQLite DB. Host/Device 이벤트·메트릭·토폴로지 통합 | xtop 분석, Perfetto 변환 |
| `.perfetto-trace` | Perfetto protobuf | 타임라인 UI |
| `.xprof` | XProfile 직렬화(바이너리) | Python 오프라인 분석 |

### 8.1 생성 경로 우선순위

- `XPTI_OUTPUT_PATH` 환경변수 > `exportProfilingCsv(path)` / `exportProfiling(path, fmt)`의 인자.
- `XPTI_OUTPUT_FORMAT`: `csv`(기본) / `xpti` / `both`.
- `xtop run`은 `-o` CLI 옵션이 최우선.

### 8.2 .xpti 파일 구조 (참고)

SQLite 테이블: host events / device events / raw metrics(L1/L2/L3/MTC/MU/PCU/Gaia) / topology / context.  
SQL로 직접 쿼리하는 것도 가능하지만 스키마는 버전에 따라 바뀔 수 있으므로 공식 xtop/xprofiler API를 권장.

### 8.3 실행 중 생성되는 보조 파일

- `*.xpti-wal`, `*.xpti-shm`: SQLite WAL 모드의 저널/shared memory. 프로세스가 정상 종료되면 본 `.xpti`에 머지되고 사라진다. 강제 종료 시 남아있으면 그 시점까지의 데이터는 복구 가능.

---

## 9. xtop로 분석하기 — 전체 레퍼런스

`xtop`은 XPTI 데이터를 분석하는 CLI다. 내부적으로 `python -m xtop`과 동일하므로 `xtop` 명령이 설치되어 있지 않으면 후자로 대체 가능하다.

### 9.1 서브커맨드 개요

```
xtop [--config CONFIG] {view,run,task,map,convert,open} ...
```

| 서브커맨드 | 목적 |
|---|---|
| `view` | 실시간 장치 모니터 (TUI) |
| `run` | 애플리케이션 실행 + 프로파일 수집 |
| `map` | Map 단위 요약 |
| `task` | 태스크 목록 / 단일 태스크 상세 |
| `convert` | `.xpti` → `.perfetto-trace` |
| `open` | Perfetto UI 로컬 서버 |

### 9.2 `xtop map <file>`

**옵션**

| 옵션 | 설명 |
|---|---|
| `--plot` | 8패널 PNG 생성 (`matplotlib` 필요) |
| `--json` | 분석 결과 JSON 내보내기 |
| `-o <path>` | PNG/JSON 출력 경로 |

**섹션별 해석 가이드**

| 섹션 | 읽는 법 |
|---|---|
| `Hardware` | 토폴로지와 주파수. 이후 섹션을 스케일링하는 기준. |
| `Duration - Host` | 유저 관점의 태스크 수행 시간 (dispatch~complete). |
| `Duration - Device` | 디바이스 관점의 active time (launch~terminate). |
| Host ↔ Device 차이 | 스케줄링·통신 오버헤드 크기. |
| `Parallelism` | `ramp_up/max_hold/ramp_down`. Ramp-down이 길면 스트래글러 의심. |
| `Skew` | Sub·Cluster 분포. `balance_score`가 1.0에 가까울수록 균등. |
| `Overhead - Map-level` | 6단계 분해 (아래 표 참조). |
| `Overhead - Task-level` | dispatch→complete 중 active가 아닌 시간. |
| `Cache` | L1/L3 hit 율. L2는 TRAT 기반으로 별도 컬럼. |
| `Memory Bandwidth` | L3 cmd 수 × 캐시라인 크기 / 시간. **추정치**. |
| `Stragglers` | 가장 바쁜/한가한 thread. ratio > 2.0이면 편중. |
| `Idle` | 태스크 간 gap 누적. `gap_count`와 함께 볼 것. |
| `Long Tail` | Stream 단위 병목 식별. |
| `Utilization` | 최소 한 번이라도 태스크를 받은 쓰레드 비율. |

**Overhead 6단계**

```
Host total = HostInit + DeviceInit + Request + Waiting + DeviceFinalize + HostFinalize
```

| 구간 | 의미 | 큰 경우 해석 |
|---|---|---|
| `HostInit` | 호스트 측 세션/자원 준비 | 세션 생성 비용 |
| `DeviceInit` | 디바이스 opcode init, 폴링 세팅 | 버퍼 allocation/프로브 init |
| `Request` | 호스트→디바이스 dispatch 큐잉 | 스케줄링/드라이버 병목 |
| `Waiting` | 디바이스 실행 대기 (launch→terminate 폴링) | 커널 자체가 느림, 혹은 배치 부족 |
| `DeviceFinalize` | 디바이스 측 종료 처리 | 후처리 커널 등 |
| `HostFinalize` | 호스트 측 결과 수집 | MemCopy-D2H, 파일 내보내기 |

### 9.3 `xtop task <file> [id]`

**옵션**

| 옵션 | 설명 |
|---|---|
| `--sort {active,overhead,id}` | 정렬 키 (기본 `id`) |
| `--filter <expr>` | 필터 예: `sub=0`, `cluster=1` |
| `--limit N` | 최대 N행 (0 = 무제한) |

목록은 `ID / Kernel / Active / Overhead / Sub / Cluster` 컬럼. 단일 태스크(ID 인자)를 지정하면:

```
[Timing]
  Host:    dispatch, complete, duration
  Device:  launch, terminate, active_time
  overhead (%)
[Placement]
  sub / cluster / mu / thread
[Cache] (task time window)
  L1/L3 hit rate, 샘플 수
[Diagnosis]
  ⚠ High overhead (xx.x% of host duration)
  ⚠ L2 miss rate above threshold
  ⚠ ...
```

**Diagnosis** 메시지는 자동 규칙 기반이므로 노이즈일 수 있다. 절대 수치와 함께 판단할 것.

### 9.4 `xtop convert`, `xtop open`

```bash
xtop convert profile.xpti                # profile.xpti.perfetto-trace 생성
xtop convert profile.xpti --json         # legacy JSON 포맷
xtop open   profile.perfetto-trace       # 로컬 서버 + 브라우저
xtop open   ./xtop_profile/              # 디렉토리 전체
xtop open   profile.perfetto-trace -p 9999
```

`open` 모드는 `flask` 필요.

### 9.5 `xtop view`, `xtop run`

```bash
sudo xtop view                           # 실시간 모니터
sudo xtop run -- ./my_app                # 수집
sudo xtop run -o ./prof --perfetto -- ./my_app
```

### 9.6 권장 워크플로

```bash
# 1. 수집
sudo xtop run -- ./my_app

# 2. 거시 상태 파악
xtop map  profile.xpti

# 3. 꼬리 태스크 찾기
xtop task profile.xpti --sort active --limit 10

# 4. 개별 파고들기
xtop task profile.xpti 17

# 5. 타임라인 시각화
xtop convert profile.xpti
xtop open    profile.xpti.perfetto-trace
```

---

## 10. 프로파일링으로 알 수 있는 것

수집 데이터로부터 읽어낼 수 있는 정보를 유형별로 정리한다.

### 10.1 실행 타이밍 / 구조

- **Wall time** (Map 전체), **Task count**, task별 avg / median / min / max / std_dev.
- **Host duration vs Device active time** → 두 값의 차이가 **스케줄링 + 통신 오버헤드**.
- **dispatch → launch → terminate → complete** 네 지점의 개별 타임스탬프.
- **Overhead 6단계** 분해(HostInit/DeviceInit/Request/Waiting/DeviceFinalize/HostFinalize).

### 10.2 병렬성 / 스케줄링

- 시간별 동시 실행 태스크 수(max/avg concurrent).
- **Ramp-up / Max-hold / Ramp-down**.
  - 긴 ramp-up → 초기 디스패치 병목.
  - 긴 ramp-down → stragglers(꼬리 태스크) 존재.
- Map 상태 전이(MapStatusChange) 로그.
- Stream 단위 병목 식별(Long Tail 섹션).

### 10.3 부하 밸런스 / 스큐

- Sub × Cluster × MU × Thread 그리드별 태스크 수와 누적 실행 시간(히트맵).
- **Balance score** (1.0 = 완전 균등).
- **Straggler ratio** — 최대 / 최소 부하 비율. 2.0↑면 상당한 편중.
- **Utilization** — 태스크를 하나라도 받은 쓰레드 비율.

### 10.4 메모리 계층 효율

| 프로브 | 대표 지표 |
|---|---|
| L1 | write/read hit ratio, bypass 수, L2 access 수 |
| L2 | TRAT / RRAT / WRAT / SRAT 개별 hit ratio, phy_cnt |
| L3 | PRAT / VRAT / WRAT / RRAT / SRAT hit ratio, araddr·awaddr 분포 |
| MTC | Meta Cache hit/miss |
| PCU | CHI 프로토콜 계층 카운터 (40+종) |
| Gaia | SMC Page / TLB hit, SSD R/W, eviction |

- L3 command 수 × cache line size / wall time ≈ **추정 메모리 대역폭**.
- 낮은 L2 hit → 데이터 지역성 문제 가능.
- Gaia SSD Read가 많으면 CXL 매핑 레이어에서 SSD fallback.

### 10.5 태스크 단위 진단

`xtop task <id>`는 단일 태스크에 대해:
- Host/Device 타임스탬프, active_time, overhead(% 포함)
- 실행된 Sub/Cluster/MU/Thread 위치
- 태스크 실행 윈도우 동안의 L1/L2/L3 hit율과 샘플 수
- 자동 진단 메시지(고오버헤드, 캐시 miss 과다 등)

### 10.6 CPU 측 동작

- Host API 호출별 enter/exit (TaskDispatch, MemCopy, StreamWait, MemAlloc/Free 등).
- MemCopy: 방향(Host↔Device, D2D), 크기, 시간.
- 사용자 정의 `XPTI_TRACE_*` 스코프.

---

## 11. 원시 CSV 컬럼 레퍼런스

Raw CSV로 내보낸 컬럼은 분석 스크립트를 쓸 때 유용하다. 주요 구조체의 `csvHeader()` 정의에서 추출.

### L1 (`L1RawData`)
```
hostUs, coretimestamp, sub, cluster, mu,
w_hit, w_miss, r_hit, r_miss,
wbyp, rbyp, scmd, mwr, mrd
```

### L2 (`L2RawData`)
```
hostUs, coretimestamp, sub, cluster,
trat_hit, trat_miss, rrat_hit, rrat_miss,
wrat_hit, wrat_miss, srat_hit, srat_miss,
phy_cnt, wbyp_cnt, rbyp_cnt,
swr_cnt, srd_cnt, mwr_cnt, mrd_cnt,
rsq_wptr, mmu_cnt, cmd_cnt
```

### L3 (`L3RawData`)
```
hostUs, coretimestamp, ddrSub, l3Index,
prat_hit, prat_miss, vrat_hit, vrat_miss,
wrat_hit, wrat_miss, rrat_hit, rrat_miss,
srat_hit, srat_miss,
awaddr, araddr,
rdty_cnt, swr_cnt, srd_cnt, mwr_cnt, mrd_cnt,
rsq_wptr, vcsq_wptr, cmd_cnt
```
> `awaddr`/`araddr`: AXI write/read 주소. 메모리 접근 패턴 분석에 활용.

### MTC (`MTCRawData`)
```
hostUs, coretimestamp, ddrSub, l3Index,
mrat_hit, mrat_miss, bisCnt, rsqWptr
```

### MU / PCU / Gaia
- MU: PC, exec count, COP req/rsp act count
- PCU: 40여 개 카운터(Req·Rwd·NDR·DRS 계열). CHI 프로토콜 인지가 필요.
- Gaia: smcPage/smcTlb hit/miss, ssdRead/Write, evictionTrigger/Hit/Done.

### Stats 집계 (`stats::L1Stats` 등)
- `global` / `perSub` / `perCluster` 3단계 집계.
- CSV 컬럼(예: L1Stats):  
  `sub,cluster,write_hit_ratio,read_hit_ratio,total_hit_ratio,write_hits,write_misses,read_hits,read_misses,total_hits,total_misses,write_bypass,read_bypass,cpu_cmd,l2_write,l2_read`

---

## 12. 증상→확인 포인트 매핑

| 증상 | 먼저 볼 곳 | 원인 후보 |
|---|---|---|
| Wall time이 긺 | `xtop map` Duration | 태스크 수 부족 / stragglers |
| Overhead 비율이 높음 | Overhead 6단계 | Request↑=스케줄링, Waiting↑=커널/배치, Finalize↑=D2H |
| 쓰레드 편중 | Skew / Stragglers / heatmap | 데이터 의존 분포 |
| L1/L2 hit 낮음 | Cache 섹션 | 지역성 불량, bypass 과다 |
| Ramp-down이 김 | Parallelism | 꼬리 태스크 |
| 단일 태스크만 느림 | `xtop task <id>` | 캐시 miss · 큰 입력 |
| 호스트가 대기 | 타임라인 gap | 동기화 / 메모리 복사 |
| SSD I/O가 보임 | Gaia stats | SMC TLB miss → SSD fallback |
| Stream 하나만 느림 | Long Tail | 의존 체인 / 배치 불균형 |
| 유휴 시간이 큼 | Idle (gap_count) | Map 간 gap / 동기화 |

---

## 13. 오버헤드와 주의사항

- 프로파일링은 **공짜가 아니다**. HostSampling 1000 ms, DeviceSampling 1 ms가 기본이며, `deviceSamplingRate`를 과하게 낮추면 오버헤드가 실행 특성을 왜곡한다.
- 필요 없는 프로브는 `enabledProbeTypes`에서 제외.
- `enabledDebugTypes`는 디버그 전용 — 평소 비활성.
- `XPTI_ENABLE=1`이 이미 켜진 상태에서 코드의 `enableProfiling()`은 **무시**된다. 이는 xtop run을 방해하지 않기 위한 의도된 동작.
- 파일 경로·포맷은 `XPTI_OUTPUT_PATH` / `XPTI_OUTPUT_FORMAT` 환경변수 > 프로그램 API `path` 인수 순서로 우선 적용됨.
- `xtop run`/`xtop view`는 root 권한 필요.
- `HostEvent`·`DeviceEvent`를 끄면 Perfetto 타임라인 해당 트랙이 비어있다.
- 짧은(µs) 커널에서는 `deviceSamplingRate`(기본 1 ms)보다 커널이 짧아 샘플이 0개일 수 있다 — 이 경우 per-task 캐시는 "session aggregate"로 대체된다 (`xtop task` 메시지 참조).

---

## 14. Python에서 결과 분석 (오프라인)

`.xprof` 파일은 `pypxl.profiler`로 열 수 있다. Python 스크립트로 host 레코드, job 메타, 디바이스 섹션(L1/L2/DDR/Timer/Mu/L0)을 순회해서 커스텀 지표를 계산할 수 있다. 전체 예시는 `lib/pxl/bindings/python/tests/xprofile_test.py`.

```python
import pypxl.profiler as xp

profile = xp.XProfile(filename="profile.xprof")

print("host records:", profile.host_record_count())

ctx = profile.context()
info = ctx.profile_info()
print(f"topology: {info.num_total_sub} subs "
      f"x {info.num_cluster_per_sub} clusters "
      f"x {info.num_mu_per_cluster} MUs "
      f"x {info.num_thread_per_mu} threads")

for job in ctx.jobs():
    print(f"job {job.job_id()} @ {job.binary_path()}  subs={job.sub_ids()}")

for rec in profile.host_records()[:10]:
    tag = "Enter" if rec.is_enter() else "Exit "
    print(f"[{rec.timestamp()}] {tag} {rec.func_name()} "
          f"(pid={rec.process_id()} tid={rec.thread_id()})")
```

raw device 데이터(per-Sub):

```python
for sub in profile.raw_sub_ids():
    common = profile.raw_common_data(sub)        # bytes
    probe  = profile.raw_user_probe_data(sub)    # bytes
    # 바이너리 포맷은 ProfileInfo(common/userProbe 주소·크기)와 함께 해석
```

`.xpti`(SQLite)를 분석하고 싶다면 표준 `sqlite3` 모듈로 직접 열 수 있다. 단, 스키마는 버전에 종속적이므로 가능하면 `xtop` CLI나 `xprofiler.core.*` 모듈(분석 유틸)을 쓰는 편이 안전하다.

---

## 15. Claude Code/DAX 환경에서 실행 시

Claude Code 등 Node.js 기반 에이전트 셸에서 CXL DAX 디바이스를 건드리는 프로그램을 그대로 실행하면 **SIGBUS**가 발생한다. 원인은 부모 프로세스가 `prctl(PR_SET_THP_DISABLE, 1)`을 해 둔 플래그가 `fork`/`exec`를 거쳐도 상속되기 때문 (자세한 분석은 `/home/worker/use_device_ko.md` 참조).

해결책은 THP를 다시 켜는 래퍼 바이너리.

```c
// thp_enable.c
#include <sys/prctl.h>
#include <unistd.h>
int main(int argc, char* argv[]) {
    prctl(PR_SET_THP_DISABLE, 0, 0, 0, 0);
    if (argc > 1) execv(argv[1], argv + 1);
    return 1;
}
```

```bash
gcc -o ~/thp_enable thp_enable.c
XPTI_ENABLE=1 XPTI_OUTPUT_PATH=./out XPTI_OUTPUT_FORMAT=xpti \
  ~/thp_enable ./my_app
```

SDK를 직접 수정할 수 있다면 초기화 경로에서 `prctl(PR_SET_THP_DISABLE, 0)` 한 줄을 호출하는 것이 더 깔끔하다.

---

## 16. 문제 해결

| 증상 | 점검 |
|---|---|
| 실행 시 SIGBUS | §15 참조. `~/thp_enable` 래퍼 사용. |
| `.xpti` 파일이 생성되지 않음 | `XPTI_ENABLE=1` 지정 여부. `XPTI_OUTPUT_PATH` 디렉토리 존재·쓰기 권한. |
| `enableProfiling()`이 아무 효과 없음 | `XPTI_ENABLE=1`가 이미 켜져 있어 무시됨. 환경변수를 unset하거나 설정을 환경변수 쪽에 맞춤. |
| Perfetto 트랙이 비어있음 | `enabledProbeTypes`에 `HostEvent`·`DeviceEvent` 포함됐는지 확인. |
| `xtop` 명령을 못 찾음 | `python3 -m xtop ...` 또는 `tools/xprofiler/install.sh` 설치. |
| Per-task 캐시가 "session aggregate" 로만 표시 | `deviceSamplingRate`가 커널 실행 시간보다 큼. 값을 낮추거나 집계값으로 해석. |
| `.xpti-wal` / `.xpti-shm`이 남음 | 프로세스가 비정상 종료. 정상 종료 시 자동 정리됨. WAL은 SQLite 도구로 병합 가능. |
| `sudo xtop run`이 permission denied | `sudo` 없이 실행. view/run은 디바이스 접근 때문에 루트 필요. |
| 대용량(.xpti)이 느림 | 필요 없는 프로브 끄기, `hostSamplingRate`/`deviceSamplingRate` 늘리기. |
| Python 바인딩이 import 안 됨 | `pypxl` 휠이 설치된 파이썬 환경인지 확인(`pip show pypxl`). |

---

## 17. 빠른 치트시트

```bash
# 0) Claude Code 환경 한정(DAX)
gcc -o ~/thp_enable ~/thp_enable.c
PREFIX="~/thp_enable"   # 일반 셸이면 빈 문자열로

# 1) 코드 수정 없이 전체 프로파일
sudo xtop run -- ./app

# 2) 환경변수만으로 실행
XPTI_ENABLE=1 XPTI_OUTPUT_PATH=./out XPTI_OUTPUT_FORMAT=xpti $PREFIX ./app

# 3) 프로세스 단일 세션
XPTI_ENABLE=1 XPTI_PROCESS_PROFILE=1 \
  XPTI_OUTPUT_PATH=./out XPTI_OUTPUT_FORMAT=xpti $PREFIX ./app

# 4) 분석
xtop map  out/session_*.xpti
xtop map  out/session_*.xpti --plot -o map.png
xtop map  out/session_*.xpti --json -o map.json
xtop task out/session_*.xpti --sort active --limit 10
xtop task out/session_*.xpti 17
xtop convert out/session_*.xpti && xtop open out/session_*.xpti.perfetto-trace
```

```cpp
// 프로그램에서 선택적 프로파일
xpti::ProfileConfig cfg{};
cfg.enabledProbeTypes = { xpti::ProbeType::L1, xpti::ProbeType::L3,
                          xpti::ProbeType::HostEvent,
                          xpti::ProbeType::DeviceEvent };
map->enableProfiling(cfg);
map->execute(...); map->synchronize();

// 원시 샘플 직접 접근
auto l1 = map->getProfilingData<xpti::QueryKey::MetricsRawL1>();
for (const auto& s : l1) { /* s.w_hit, s.r_miss, ... */ }

// 집계만 필요
auto s = map->getProfilingData<xpti::QueryKey::MetricsStatsL1>();
double hr = s.global.cacheHitStats.getHitRatio();

// 필터
auto f = xpti::QueryFilter::BySubs({0,1});
auto ev = map->getProfilingData<xpti::QueryKey::EventsDevice>(f);

// 파일로
map->exportProfiling("./out", xpti::ExportFormat::Both);
```

```cpp
// 사용자 정의 스코프
{ XPTI_TRACE_SCOPE("preprocess"); doPreprocess(); }
XPTI_TRACE_BEGIN("async");  kickoff(); /* ... */  XPTI_TRACE_END("async");
```

---

## 18. 참고 경로

### XPTI / PXL 소스
- 공개 API: `lib/pxl/module/xpti/xpti/include/xpti/xpti.hpp`
- 타입·enum: `lib/pxl/module/xpti/xpti/include/xpti/xpti_types.hpp`
- 타입 추론: `lib/pxl/module/xpti/xpti/include/xpti/xpti_data_value.hpp`
- 집계 통계: `lib/pxl/module/xpti/xpti/include/xpti/stats/*.hpp`
- PXL 통합 API: `lib/pxl/include/pxl/runtime/map.hpp` (`enableProfiling`, `exportProfiling`)
- PXL 구현: `lib/pxl/src/runtime/impl/map_impl.cpp` (env 자동화·export 경로)

### 도구
- `tools/xprofiler/xtop/` — `xtop` CLI
- `tools/xprofiler/xprofiler/core/` — 분석 유틸 (`analyzer`, `converter`, `parser`, `symbolizer`)
- `tools/xprofiler/xtop/xtop_config.yaml` — 기본 설정

### 문서
- `docs/tools/xtop.md` — xtop 개요·view/run 모드
- `docs/tools/profiler.md` — map/task/convert/open 상세

### 샘플 / 테스트
- `tests/profile_test/pxl_profile_api/test_enable_profiling.cpp` — 기본 플로우
- `tests/profile_test/pxl_profile_api/test_multi_map_profile.cpp` — 병렬 Map
- `tests/profile_test/pxl_profile_api/test_process_profile.cpp` — Process 세션
- `tests/profile_test/pxl_profile_api/test_env_auto_enable.cpp` — `XPTI_ENABLE=1` 경로
- `lib/pxl/bindings/python/tests/xprofile_test.py` — Python 바인딩 예시
