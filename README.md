# my_workspace

개발 환경 설정 (Neovim, Docker, Claude Code)

## 설치

### 호스트 환경 (직접 설치)
```bash
source ./execute_with_source.sh
```

### Docker 환경
```bash
./launch_docker_container.sh
```
실행 시 preflight check → 리포 clone → 컨테이너 생성 → 환경 설치가 자동으로 진행됩니다.

컨테이너 내부에서 `execute_with_source.sh`가 자동 실행되어 nvim, glow 등이 설치됩니다.

---

# Neovim Configuration (v0.11+)

## 에디터 핵심 단축키

| 단축키 | 기능 | 비고 |
| :--- | :--- | :--- |
| **`Ctrl+n`** | 파일 탐색기 토글 | nvim-tree |
| **`<Space>ff`** | 파일 찾기 | Telescope |
| **`<Space>fg`** | 텍스트 검색 (ripgrep) | Telescope |
| **`<Space>fb`** | 버퍼 목록 | Telescope |
| **`Ctrl+o`** | 이전 위치로 이동 | Jump List |
| **`Ctrl+i`** | 다음 위치로 이동 | Jump List |
| **`<Tab>` / `<S-Tab>`** | 자동완성 목록 이동 | nvim-cmp |
| **`<C-Space>`** | 자동완성 강제 호출 | nvim-cmp |
| **`gcc`** | 현재 줄 주석 토글 | Comment.nvim |
| **`gc`** (Visual) | 선택 영역 주석 토글 | Comment.nvim |
| **`Esc`** | 검색 하이라이트 해제 | |

## LSP 단축키

| 단축키 | 기능 |
| :--- | :--- |
| **`K`** | Hover (타입 정보/문서) |
| **`gd`** | Go to Definition |
| **`gD`** | Go to Declaration |
| **`gi`** | Go to Implementation |
| **`gr`** | Go to References |
| **`gl`** | 에러 메시지 팝업 |
| **`<Space>rn`** | Rename (일괄 이름 변경) |
| **`<Space>ca`** | Code Action (퀵 픽스) |
| **`[d` / `]d`** | 다음/이전 진단 이동 |

## 추가 기능

| 기능 | 설명 |
| :--- | :--- |
| **커서 단어 하이라이트** | 동일 단어 자동 강조 (vim-illuminate) |
| **괄호 자동 완성** | `(` 입력 시 `)` 자동 생성 (nvim-autopairs) |
| **Git 변경 표시** | sign column에 +/-/~ 표시 (gitsigns) |
| **모드별 배경색** | Insert 모드에서 배경이 차가운 톤으로 변경 |
| **한글 langmap** | 한글 입력 상태에서도 Normal 모드 명령 동작 (SSH/remote 호환) |

---

## 프로젝트 구조

```
my_workspace/
├── execute_with_source.sh       # 전체 환경 설정 (source로 실행)
├── launch_docker_container.sh   # Docker 환경 점검 + 컨테이너 생성/실행
├── github_token.txt             # GitHub token (git-ignored)
├── claude_token.txt             # Claude OAuth token (git-ignored)
├── nvim/
│   ├── init.lua                 # 메인 설정 파일
│   ├── install.sh               # Neovim 설치 스크립트
│   ├── keyremap.lua             # 키 리매핑 설정
│   ├── lua/
│   │   ├── plugins/
│   │   │   └── init.lua        # 플러그인 설정
│   │   └── lsp/
│   │       └── lspconfig.lua   # LSP 서버 설정
```

## 포함된 기능

- **Color Scheme**: OneDark Darker
- **File Explorer**: nvim-tree
- **Status Line**: lualine
- **Syntax Highlight**: Treesitter
- **LSP**: Native Neovim 0.11+ API
  - C/C++ (clangd)
  - Rust (rust_analyzer)
  - Lua (lua_ls)
  - Bash (bash-language-server)
- **Fuzzy Finder**: Telescope
- **Auto Completion**: nvim-cmp
- **Word Highlight**: vim-illuminate
- **Auto Pairs**: nvim-autopairs
- **Git Signs**: gitsigns
- **Comment Toggle**: Comment.nvim

---

# Windows Terminal 단축키

## 창 분할
- `Alt+Shift+-` : 수평 분할
- `Alt+Shift++` : 수직 분할

## 창 간 이동
- `Alt+방향키` : 해당 방향의 창으로 이동

## 기타
- `Ctrl+Shift+W` : 현재 창 닫기
- `Alt+Shift+W` : 모든 창 닫기
