# Neovim Configuration (v0.11+)

현대적인 Neovim 설정 with LSP, Treesitter, **GitHub Copilot** 지원

## 설치

```bash
cd /shared/neovim-config
chmod +x install.sh
./install.sh
```

설치 후 `nvim`을 실행하면 Lazy.nvim이 자동으로 플러그인을 설치합니다.

## GitHub Copilot 설정

### 1. Node.js 확인
```bash
node -v  # v18 이상 필요
```

### 2. Neovim에서 인증
```vim
:Copilot auth
```
브라우저에서 인증 코드를 입력하여 GitHub 계정과 연동합니다.

## 에디터 핵심 단축키 (Vim 기본 및 플러그인)

| 단축키 | 기능 | 설명 | 비고 |
| :--- | :--- | :--- | :--- |
| **`Ctrl` + `n`** | 파일 탐색기 토글 | Nvim-Tree 파일 탐색기 창을 열거나 닫습니다. | `nvim-tree.lua` |
| **`<Space>ff`** | 파일 찾기 | Telescope로 파일 검색 | `Telescope` |
| **`<Space>fg`** | 텍스트 검색 | ripgrep으로 전체 검색 | `Telescope` |
| **`<Space>fb`** | 버퍼 목록 | 열린 파일 목록 표시 | `Telescope` |
| **`Ctrl` + `o`** | 뒤로 가기 (Go Back) | `gd`, `gr` 등으로 이동했던 **이전 위치**로 되돌아갑니다. | Vim Jump List |
| **`Ctrl` + `i`** | 앞으로 가기 (Go Forward) | `Ctrl` + `o`로 되돌아온 후 **다음 위치**로 이동합니다. | Vim Jump List |
| **`<Tab>` / `<S-Tab>`** | 자동완성/스니펫 이동 | 자동완성 목록에서 이동하거나, 스니펫 내부에서 점프합니다. | `nvim-cmp`, `LuaSnip` |
| **`<C-Space>`** | 자동완성 호출 | 언제든 강제로 자동완성 목록을 띄웁니다. | `nvim-cmp` |

## GitHub Copilot 단축키

### 자동 완성 (In-line Suggestion)
| 단축키 | 기능 | 설명 |
| :--- | :--- | :--- |
| **`<C-l>`** | Copilot 제안 수락 | 회색으로 표시된 Copilot 제안을 받아들입니다 |
| **`<C-j>`** | 다음 제안 | 다음 Copilot 제안으로 이동 |
| **`<C-k>`** | 이전 제안 | 이전 Copilot 제안으로 이동 |
| **`<C-h>`** | 제안 무시 | 현재 Copilot 제안을 숨깁니다 |

### Copilot Chat (대화형 코드 작성)
| 단축키 | 기능 | 설명 | 모드 |
| :--- | :--- | :--- | :--- |
| **`<Space>cc`** | Copilot Chat 토글 | 대화형 코드 작성 창 열기/닫기 | Normal/Visual |
| **`<Space>ce`** | 코드 설명 | `v`로 선택한 코드를 한국어로 설명 | Visual |
| **`<Space>cf`** | 코드 수정 | `v`로 선택한 코드의 버그 수정 | Visual |
| **`<Space>co`** | 코드 최적화 | `v`로 선택한 코드 성능 최적화 | Visual |
| **`<Space>cr`** | 코드 리뷰 | `v`로 선택한 코드 리뷰 및 개선점 제안 | Visual |
| **`<Space>ct`** | 테스트 생성 | `v`로 선택한 코드에 대한 테스트 작성 | Visual |
| **`<Space>cd`** | 문서 생성 | `v`로 선택한 코드에 문서화 주석 추가 | Visual |

**Visual 모드 사용법:**
1. `v` 누르기 (문자 단위) 또는 `V` (줄 단위)
2. 위 단축키 실행

## LSP 코드 내비게이션 및 기능

(LSP 서버가 로드된 상태에서 작동하며, C/C++ 파일에서 주로 사용됩니다.)

| 단축키 | 기능 | 설명 |
| :--- | :--- | :--- |
| **`K`** | 키워드 정보 (Hover) | 커서가 위치한 함수, 변수, 키워드의 **타입 정보나 문서(Doc)**를 팝업으로 띄웁니다. |
| **`gd`** | Go to Definition | 커서가 위치한 토큰의 **정의(구현부)**로 이동합니다. (가장 많이 씀) |
| **`gD`** | Go to Declaration | 커서가 위치한 토큰의 **선언부(헤더 파일)**로 이동합니다. |
| **`gi`** | Go to Implementation | 인터페이스나 가상 함수의 실제 **구현부**로 이동합니다. |
| **`gr`** | Go to References | 현재 토큰이 **사용된 모든 곳**을 찾아서 목록으로 보여줍니다. |
| **`<Space>` + `rn`** | Rename (일괄 이름 변경) | 변수나 함수 이름을 프로젝트 전체에 걸쳐 **일괄적으로 변경**합니다. |
| **`<Space>` + `ca`** | Code Action (퀵 픽스) | 퀵 픽스 메뉴를 엽니다. (예: 누락된 헤더 추가, 코드 구조 변경 등) |
| **`<Space>` + `f`** | Format | 현재 파일의 코드를 **자동 정렬(포맷팅)** 합니다. |
| **`[d` / `]d`** | 다음/이전 진단 | LSP가 찾은 에러(`Error`)나 경고(`Warning`) 사이를 이동합니다. |

## 추가 기능 (vim-illuminate)

| 단축키 | 기능 | 설명 |
| :--- | :--- | :--- |
| **커서 이동** | 커서 단어 하이라이트 | 커서를 단어(키워드 포함) 위에 올리면, **문서 내의 동일한 모든 단어**를 강조 표시합니다. |
| **`<Alt>` + `n`** | 다음 강조 단어로 이동 | 하이라이트 된 **다음** 단어 위치로 이동합니다. |
| **`<Alt>` + `p`** | 이전 강조 단어로 이동 | 하이라이트 된 **이전** 단어 위치로 이동합니다. |

---

## 프로젝트 구조

```
neovim-config/
├── init.lua                  # 메인 설정 파일
├── install.sh                # 자동 설치 스크립트
├── lua/
│   ├── plugins/
│   │   ├── init.lua         # 기본 플러그인 (Treesitter, LSP, Telescope 등)
│   │   └── copilot.lua      # GitHub Copilot 전용 (고립된 모듈) ⭐
│   └── lsp/
│       └── lspconfig.lua    # LSP 서버 설정 (clangd, rust_analyzer, lua_ls)
```

## 🔧 Copilot 업데이트 방법

Copilot 관련 설정을 변경하려면 **`lua/plugins/copilot.lua`** 파일만 수정하면 됩니다.
다른 플러그인 설정과 완전히 독립되어 있어 안전하게 관리할 수 있습니다.

### Copilot 비활성화
`lua/plugins/copilot.lua` 파일 전체를 삭제하거나 빈 배열을 반환하도록 수정:
```lua
return {}
```

## 포함된 기능

- **Color Scheme**: Tokyo Night Storm
- **File Explorer**: nvim-tree
- **Status Line**: lualine (IME 상태 표시 포함 🇰🇷/🇺🇸)
- **Syntax Highlight**: Treesitter
- **LSP**: Native Neovim 0.11+ API
  - C/C++ (clangd)
  - Rust (rust_analyzer)
  - Lua (lua_ls)
- **Fuzzy Finder**: Telescope
- **Auto Completion**: nvim-cmp + **Copilot 통합**
- **Word Highlight**: vim-illuminate
- **AI Assistant**: GitHub Copilot + Copilot Chat

## 파일 목록 (참고)

| 파일 | 역할 |
| :--- | :--- |
| `init.lua` | 메인 진입점. 기본 설정 및 Lazy.nvim 로드 |
| `install.sh` | 환경 설정, Neovim 바이너리 설치 및 의존성 설치 스크립트 |
| `lua/plugins/init.lua` | 기본 플러그인 명세 (LSP, Treesitter, Nvim-Tree 등) |
| `lua/plugins/copilot.lua` | **GitHub Copilot 전용 모듈** (고립된 구조) ⭐ |
| `lua/lsp/lspconfig.lua` | **`vim.lsp.config` 기반**의 LSP 서버별 상세 설정 및 키매핑 정의 |
