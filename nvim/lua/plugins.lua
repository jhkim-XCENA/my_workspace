return {
    -- 1. Color Scheme (Tokyo Night)
    {
        "folke/tokyonight.nvim",
        priority = 1000,
        config = function()
            vim.cmd.colorscheme("tokyonight-storm")
        end,
    },

    -- 2. File Explorer (Nvim-Tree)
    {
        "nvim-tree/nvim-tree.lua",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            require("nvim-tree").setup({
                sort = { sorter = "case_sensitive" },
                view = { width = 30 },
                renderer = { group_empty = true },
                filters = { dotfiles = true },
            })
            vim.keymap.set("n", "<C-n>", ":NvimTreeToggle<CR>", { silent = true })
        end,
    },

    -- 3. Status Line (Lualine)
    {
        "nvim-lualine/lualine.nvim",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        opts = {
            options = { theme = "tokyonight" },
        },
    },

    -- 4. Treesitter (Syntax Highlight) - 수정됨
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        -- main = "nvim-treesitter.configs", 
        opts = {
            ensure_installed = { "c", "cpp", "lua", "vim", "vimdoc", "bash", "python", "rust" },
            auto_install = true,
            highlight = { enable = true },
            indent = { enable = true },
        },
    },

    -- 5. LSP Support (nvim 0.11+ uses native vim.lsp.config)
    {
        "hrsh7th/cmp-nvim-lsp",
        config = function()
            -- LSP 설정은 lua/lsp/lspconfig.lua에서 로드됨
            require("lsp.lspconfig")
        end,
    },
    -- 6. Fuzzy Finder (Telescope)
    {
        "nvim-telescope/telescope.nvim",
        dependencies = { "nvim-lua/plenary.nvim" },
        config = function()
            local builtin = require('telescope.builtin')
            vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = 'Find Files' })
            vim.keymap.set('n', '<leader>fg', builtin.live_grep, { desc = 'Live Grep' })
            vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = 'Find Buffers' })
            vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = 'Help Tags' })
        end,
    },

    -- 7. 단어 강조 (vim-illuminate)
    {
        "RRethy/vim-illuminate",
        event = { "BufReadPost", "InsertEnter" }, -- 파일을 읽거나 입력 모드 들어갈 때 로드
        config = function()
            require("illuminate").configure({
                -- 하이라이트 대기 시간 (밀리초). 너무 짧으면 정신없으니 200~300 권장
                delay = 200,
                
                -- 특정 파일타입에서는 비활성화 (예: 파일 탐색기 등)
                filetypes_denylist = {
                    "dirvish",
                    "fugitive",
                    "nvimtree",
                    "TelescopePrompt",
                },
            })
            
            -- 색상 설정 (Tokyonight 테마가 알아서 잡지만, 커스텀하고 싶다면 아래 주석 해제)
            -- vim.api.nvim_set_hl(0, "IlluminatedWordText", { link = "Visual" })
            -- vim.api.nvim_set_hl(0, "IlluminatedWordRead", { link = "Visual" })
            -- vim.api.nvim_set_hl(0, "IlluminatedWordWrite", { link = "Visual" })
        end,
    },
    -- 8. 자동완성 엔진 (nvim-cmp)
    {
        "hrsh7th/nvim-cmp",
        event = "InsertEnter", -- 입력 모드 진입 시 로드
        dependencies = {
            "hrsh7th/cmp-nvim-lsp",     -- LSP 소스
            "hrsh7th/cmp-buffer",       -- 현재 파일 내 단어 추천
            "hrsh7th/cmp-path",         -- 파일 경로 추천
            "L3MON4D3/LuaSnip",         -- 스니펫 엔진 (필수)
            "saadparwaiz1/cmp_luasnip", -- 스니펫 연결
        },
        config = function()
            local cmp = require("cmp")
            local luasnip = require("luasnip")

            cmp.setup({
                snippet = {
                    expand = function(args)
                        luasnip.lsp_expand(args.body) -- 스니펫 확장 설정
                    end,
                },
                -- 키 매핑 설정
                mapping = cmp.mapping.preset.insert({
                    ['<C-b>'] = cmp.mapping.scroll_docs(-4), -- 문서 스크롤 위로
                    ['<C-f>'] = cmp.mapping.scroll_docs(4),  -- 문서 스크롤 아래로
                    ['<C-Space>'] = cmp.mapping.complete(),  -- 강제 자동완성 호출
                    ['<CR>'] = cmp.mapping.confirm({ select = true }), -- 엔터로 선택
                    
                    -- 탭(Tab)으로 항목 이동
                    ['<Tab>'] = cmp.mapping(function(fallback)
                        if cmp.visible() then
                            cmp.select_next_item()
                        elseif luasnip.expand_or_jumpable() then
                            luasnip.expand_or_jump()
                        else
                            fallback()
                        end
                    end, { "i", "s" }),
                    
                    ['<S-Tab>'] = cmp.mapping(function(fallback)
                        if cmp.visible() then
                            cmp.select_prev_item()
                        elseif luasnip.jumpable(-1) then
                            luasnip.jump(-1)
                        else
                            fallback()
                        end
                    end, { "i", "s" }),
                }),
                -- 추천 소스 우선순위
                sources = cmp.config.sources({
                    { name = "nvim_lsp" }, -- LSP (C++, Rust 등)
                    { name = "luasnip" },  -- 스니펫
                }, {
                    { name = "buffer" },   -- 버퍼 내 단어
                    { name = "path" },     -- 파일 경로
                })
            })
        end,
    },   
}
