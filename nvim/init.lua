-- ~/.config/nvim/init.lua

-- 1. Basic Options (UI & Behavior)
vim.g.mapleader = " "         -- Leader key를 Space로 설정 (매우 중요)
vim.g.maplocalleader = "\\"

local opt = vim.opt

opt.number = true             -- 줄 번호 표시
opt.relativenumber = false    -- 상대 라인 번호 끄기 (취향)
opt.cursorline = true         -- 현재 줄 강조
opt.tabstop = 2               -- 탭 크기 (C++ 표준 4칸 추천, 원하면 2로 변경)
opt.shiftwidth = 2            -- 들여쓰기 크기
opt.expandtab = true          -- 탭을 스페이스로 변환
opt.autoindent = true         -- 자동 들여쓰기
opt.smartindent = false       -- 스마트 들여쓰기
opt.cindent = false           -- C/C++ 스타일 들여쓰기
opt.wrap = false              -- 줄바꿈 안 함
opt.ignorecase = true         -- 검색 시 대소문자 무시
opt.smartcase = true          -- 대문자 섞이면 대소문자 구분
opt.termguicolors = true      -- 24bit 트루컬러 사용
opt.scrolloff = 8             -- 스크롤 시 위아래 여백 확보
opt.updatetime = 50           -- 반응 속도 (기본 4000ms -> 50ms로 단축)
opt.virtualedit = "onemore"   -- 커서가 줄의 끝을 넘어 이동 가능 (Normal mode에서)
opt.guicursor = "n-c:ver25-blinkwait200-blinkon200-blinkoff200,i-ci-ve:ver25-blinkwait200-blinkon200-blinkoff200,r-cr:block-blinkwait200-blinkon200-blinkoff200,o:hor50,v:block-blinkwait200-blinkon200-blinkoff200"  -- Normal=세로선, Insert=우향화살표, Visual/Replace=블록, 0.2초 깜빡임
opt.clipboard = "unnamedplus" -- 시스템 클립보드 사용
vim.g.clipboard = "osc52"    -- SSH/remote에서 OSC 52로 클립보드 복사
opt.cmdheight = 1
-- opt.guifont = "JetBrainsMono Nerd Font:h20"  -- 명령줄 글자 크기 20pt
opt.autoread = true       -- 파일이 외부에서 수정되면 자동 새로고침
opt.signcolumn = "yes"    -- sign column 항상 표시 (git/diagnostic 표시 시 화면 흔들림 방지)

-- 한글 지원
opt.encoding = "utf-8"
opt.fileencoding = "utf-8"

-- 한글 langmap: 한글 입력 상태에서도 Normal 모드 명령이 동작하도록 매핑
-- (SSH/remote 환경에서 ibus 없이 동작)
opt.langmap = table.concat({
    -- 하단 자음 (ㅋㅌㅊㅍㅎ → lower)
    "ㅁa", "ㅠb", "ㅊc", "ㅇd", "ㄷe", "ㄹf", "ㅎg", "ㅗh", "ㅑi", "ㅓj",
    "ㅏk", "ㅣl", "ㅡm", "ㅜn", "ㅐo", "ㅔp", "ㅂq", "ㄱr", "ㄴs", "ㅅt",
    "ㅕu", "ㅍv", "ㅈw", "ㅌx", "ㅛy", "ㅋz",
    -- 상단 (Shift+자음 → upper)
    "ㅁA", "ㅠB", "ㅊC", "ㅇD", "ㄸE", "ㄹF", "ㅎG", "ㅗH", "ㅑI", "ㅓJ",
    "ㅏK", "ㅣL", "ㅡM", "ㅜN", "ㅒO", "ㅖP", "ㅃQ", "ㄲR", "ㄴS", "ㅆT",
    "ㅕU", "ㅍV", "ㅉW", "ㅌX", "ㅛY", "ㅋZ",
}, ",")

-- Swap/Undo 설정
opt.swapfile = false
opt.backup = false
opt.undofile = true
opt.undodir = vim.fn.stdpath("state") .. "/undo"

-- 2. Bootstrap Lazy.nvim (The modern plugin manager)
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- 3. Load Plugins & Configs
require("lazy").setup({
    spec = {
        -- 플러그인 명세를 plugins/ 폴더에서 로드
        -- plugins/init.lua - 기본 플러그인
        { import = "plugins" },
    },
    checker = { enabled = true }, -- 플러그인 업데이트 자동 확인
})

-- Visual Mode에서 a를 누르면 Selection을 해제(Esc)하고 즉시 Insert(i) 모드로 진입
vim.keymap.set('v', 'a', '<Esc>i', { noremap = true, silent = true })

-- Esc로 검색 하이라이트 해제
vim.keymap.set('n', '<Esc>', '<cmd>noh<CR>', { noremap = true, silent = true })

-- 4. Load Extra Configs (LSP, Treesitter 등은 플러그인 파일에서 로드되지만 명시적 로드 필요 시)
-- Lazy.nvim 방식에서는 보통 plugins/ 폴더 내에서 config() 함수로 처리하는 것이 깔끔합니다.
-- 하지만 기존 구조를 유지하기 위해 아래 require를 유지하되, 내용은 Lazy spec에 맞게 수정했습니다.

-- 5. 모드별 배경색 변경 (Insert = 차가운 톤, VS Code Dark+ 기반)
local normal_bg = "#1e1e1e"
local insert_bg = "#1e2a35"

vim.api.nvim_create_autocmd("ModeChanged", {
    pattern = "*:i*",
    callback = function()
        vim.api.nvim_set_hl(0, "Normal", { bg = insert_bg })
    end,
})
vim.api.nvim_create_autocmd("ModeChanged", {
    pattern = "i*:*",
    callback = function()
        vim.api.nvim_set_hl(0, "Normal", { bg = normal_bg })
    end,
})

-- 6. Visual mode 선택 하이라이트 색상 (VS Code Dark+ selection color)
vim.api.nvim_set_hl(0, "Visual", { bg = "#264f78" })

-- 키 입력 타이밍 설정 (방향키 딜레이 해결)
opt.timeoutlen = 300        -- 매핑 완성을 기다리는 시간 (ms) - 500에서 300으로 단축
opt.ttimeoutlen = 0         -- 터미널 시퀀스 타이밍 (즉시 처리!) - 0ms로 설정하여 딜레이 완전 제거

-- 키 입력 타이밍 설정 - keyremap.lua 로드
local config_path = vim.fn.stdpath("config")
dofile(config_path .. "/keyremap.lua")
