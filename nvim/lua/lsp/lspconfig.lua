-- lua/lsp/lspconfig.lua

-- 1. LSP Keymaps (LSP가 연결되면 자동으로 키맵 적용)
-- v0.11부터는 이 방식이 표준이며, 변경되지 않았습니다.
vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('UserLspConfig', { clear = true }),
    callback = function(ev)
        local opts = { buffer = ev.buf, silent = true }
        local keymap = vim.keymap.set

        -- 키 매핑
        keymap('n', 'gD', vim.lsp.buf.declaration, opts)     -- 선언으로 이동
        keymap('n', 'gd', vim.lsp.buf.definition, opts)      -- 정의로 이동
        keymap('n', 'gl', vim.diagnostic.open_float, opts)   -- 에러 메시지 창 띄우기
        keymap('n', 'K', vim.lsp.buf.hover, opts)            -- 설명 보기
        keymap('n', 'gi', vim.lsp.buf.implementation, opts)  -- 구현체 보기
        keymap('n', '<space>rn', vim.lsp.buf.rename, opts)   -- 이름 변경
        keymap('n', '<space>ca', vim.lsp.buf.code_action, opts) -- 코드 액션
        keymap('n', 'gr', vim.lsp.buf.references, opts)      -- 참조 찾기
        
        -- 포맷팅
        keymap('n', '<space>f', function()
            vim.lsp.buf.format { async = true }
        end, opts)
    end,
})

-- 2. 서버 설정 (Neovim 0.11+ Native API)
-- nvim-cmp와 연동을 위한 capabilities 설정
local capabilities = require('cmp_nvim_lsp').default_capabilities()

-- [C/C++] clangd
vim.lsp.config.clangd = {
    cmd = {
        "clangd",
        "--background-index",
        "--clang-tidy",
        "--header-insertion=iwyu",
        "--completion-style=detailed",
        "--function-arg-placeholders",
    },
    capabilities = capabilities,
    root_markers = { '.git', 'compile_commands.json' },
    filetypes = { 'c', 'cpp', 'objc', 'objcpp', 'cuda', 'proto', 'h', 'hpp', 'hh', 'hxx' },
}
vim.lsp.enable('clangd')

-- [Rust] rust_analyzer
vim.lsp.config.rust_analyzer = {
    capabilities = capabilities,
    settings = {
        ["rust-analyzer"] = {
            checkOnSave = {
                command = "clippy",
            },
        },
    },
}
vim.lsp.enable('rust_analyzer')

-- [Python] pyright (필요시 주석 해제)
-- vim.lsp.config.pyright = { capabilities = capabilities }
-- vim.lsp.enable('pyright')

-- [Lua] lua_ls (Neovim 설정용)
vim.lsp.config.lua_ls = {
    capabilities = capabilities,
    settings = {
        Lua = {
            runtime = { version = 'LuaJIT' },
            diagnostics = { globals = { 'vim' } },
            workspace = {
                library = vim.api.nvim_get_runtime_file("", true),
                checkThirdParty = false, 
            },
            telemetry = { enable = false },
        },
    },
}
vim.lsp.enable('lua_ls')

vim.diagnostic.config({
  signs = false,  -- 왼쪽 거터(Gutter)의 E, W 기호를 숨김
})

-- 3. 진단(Diagnostic) UI 설정
vim.diagnostic.config({
  signs = false,       -- 왼쪽 아이콘(E, W)은 끄고 (아까 요청하신 부분)
  virtual_text = true, -- [중요] 코드 옆에 에러 메시지 텍스트는 켜기
  underline = true,    -- 밑줄 켜기
  update_in_insert = false, -- 입력 도중에는 갱신하지 않음 (선택 사항)
})

-- [Bash] bashls (Shell Script)
vim.lsp.config.bashls = {
    capabilities = capabilities,
    cmd = { "bash-language-server", "start" },
    filetypes = { "sh", "bash" }, -- sh, bash 파일에서만 동작
}
vim.lsp.enable('bashls')
