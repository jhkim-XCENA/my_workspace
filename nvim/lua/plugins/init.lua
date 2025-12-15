-- lua/plugins/init.lua
-- 기본 플러그인 설정 (Copilot 제외)

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
        config = function()
            -- IME 상태 감지 함수
            local function get_ime_status()
                local handle = io.popen("ibus engine 2>/dev/null")
                if handle then
                    local result = handle:read("*a")
                    handle:close()
                    if result and result:match("hangul") then
                        return "🇰🇷 한글"
                    end
                end
                return "🇺🇸 EN"
            end

            require('lualine').setup({
                options = { 
                    theme = "tokyonight",
                    component_separators = { left = '|', right = '|'},
                },
                sections = {
                    lualine_a = {'mode'},
                    lualine_b = {'branch', 'diff', 'diagnostics'},
                    lualine_c = {'filename'},
                    lualine_x = {
                        get_ime_status,  -- IME 상태 표시
                        'encoding', 
                        'fileformat', 
                        'filetype'
                    },
                    lualine_y = {'progress'},
                    lualine_z = {'location'}
                },
                -- 업데이트 주기 조정 (IME 상태 반영)
                refresh = {
                    statusline = 200,  -- 200ms마다 업데이트
                }
            })
        end,
    },

    -- 4. Treesitter (Syntax Highlight)
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
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
        event = { "BufReadPost", "InsertEnter" },
        config = function()
            require("illuminate").configure({
                delay = 200,
                filetypes_denylist = {
                    "dirvish",
                    "fugitive",
                    "nvimtree",
                    "TelescopePrompt",
                },
            })
        end,
    },

    -- 8. 자동완성 엔진 (nvim-cmp)
    {
        "hrsh7th/nvim-cmp",
        event = "InsertEnter",
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
                        luasnip.lsp_expand(args.body)
                    end,
                },
                mapping = cmp.mapping.preset.insert({
                    ['<C-b>'] = cmp.mapping.scroll_docs(-4),
                    ['<C-f>'] = cmp.mapping.scroll_docs(4),
                    ['<C-Space>'] = cmp.mapping.complete(),
                    ['<CR>'] = cmp.mapping.confirm({ select = true }),
                    
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
                -- Copilot을 포함한 추천 소스 우선순위
                sources = cmp.config.sources({
                    { name = "copilot", group_index = 2 },  -- Copilot (최우선)
                    { name = "nvim_lsp", group_index = 2 }, -- LSP
                    { name = "luasnip", group_index = 2 },  -- 스니펫
                }, {
                    { name = "buffer" },   -- 버퍼 내 단어
                    { name = "path" },     -- 파일 경로
                }),
                -- Copilot 아이콘 추가
                formatting = {
                    format = function(entry, vim_item)
                        -- 소스별 아이콘 표시
                        local icons = {
                            copilot = "",
                            nvim_lsp = "",
                            luasnip = "",
                            buffer = "﬘",
                            path = "",
                        }
                        vim_item.kind = string.format('%s %s', icons[entry.source.name] or '', vim_item.kind)
                        return vim_item
                    end
                },
            })
        end,
    },

    -- 9. Markdown Viewer (터미널에서 보기 좋게 렌더링)
    {
        "tadmccorkle/markdown.nvim",
        ft = { "markdown" },
        opts = {
            hooks = {
                setloclist = function(buf)
                    -- 마크다운 헤더를 location list에 표시
                end,
            },
            on_attach = function(bufnr)
                vim.keymap.set('n', '<leader>mp', ':MarkdownPreview<CR>', { buffer = bufnr, noremap = true, silent = true })
            end,
        },
    },
}
