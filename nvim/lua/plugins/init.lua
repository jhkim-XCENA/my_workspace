-- lua/plugins/init.lua
-- 기본 플러그인 설정 (Copilot 제외)

return {
    -- 1. Color Scheme (OneDark Darker)
    {
        "olimorris/onedarkpro.nvim",
        priority = 1000,
        config = function()
            require("onedarkpro").setup({
                style = "darker",
            })
            vim.cmd.colorscheme("onedark")
        end,
    },

    -- 2. File Explorer (Nvim-Tree) - 명시적으로 호출할 때만 로드
    {
        "nvim-tree/nvim-tree.lua",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        cmd = { "NvimTreeToggle", "NvimTreeOpen", "NvimTreeFocus" }, -- 명령어 사용 시에만 로드
        keys = {
            { "<C-n>", ":NvimTreeToggle<CR>", desc = "Toggle file tree", silent = true }
        },
        config = function()
            require("nvim-tree").setup({
                sort = { sorter = "case_sensitive" },
                view = { width = 30 },
                renderer = { group_empty = true },
                filters = { dotfiles = true },
            })
        end,
    },

    -- 3. Status Line (Lualine)
    {
        "nvim-lualine/lualine.nvim",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            -- IME 상태 감지 함수 (캐시 추가로 성능 개선)
            local ime_status_cache = { value = "🇺🇸 EN", timestamp = 0 }
            local function get_ime_status()
                local current_time = vim.loop.hrtime() / 1000000 -- ms로 변환
                -- 1초 이내면 캐시된 값 반환 (빈번한 프로세스 실행 방지)
                if current_time - ime_status_cache.timestamp < 1000 then
                    return ime_status_cache.value
                end
                
                local handle = io.popen("ibus engine 2>/dev/null")
                if handle then
                    local result = handle:read("*a")
                    handle:close()
                    if result and result:match("hangul") then
                        ime_status_cache.value = "🇰🇷 한글"
                    else
                        ime_status_cache.value = "🇺🇸 EN"
                    end
                    ime_status_cache.timestamp = current_time
                end
                return ime_status_cache.value
            end

            require('lualine').setup({
                options = { 
                    theme = "onedark",
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
                -- 업데이트 주기 조정 (IME 상태 반영을 위한 최적화)
                refresh = {
                    statusline = 500,  -- 500ms마다 업데이트 (200에서 증가, CPU 부하 감소)
                }
            })
        end,
    },

    -- 4. Treesitter (Syntax Highlight) - 최적화된 설정
    {
        "nvim-treesitter/nvim-treesitter",
        event = { "BufReadPost", "BufNewFile" }, -- 파일 열 때만 로드
        build = ":TSUpdate",
        opts = {
            ensure_installed = { "c", "cpp", "lua", "vim", "vimdoc", "bash", "python", "rust" },
            auto_install = true,
            highlight = { 
                enable = true,
                additional_vim_regex_highlighting = false, -- Vim regex 하이라이팅 비활성화 (성능 개선)
            },
            indent = { enable = true },
            -- 증분 선택 비활성화 (사용하지 않는다면)
            incremental_selection = { enable = false },
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

    -- 6. Fuzzy Finder (Telescope) - 명령어 사용 시에만 로드
    {
        "nvim-telescope/telescope.nvim",
        dependencies = { "nvim-lua/plenary.nvim" },
        cmd = "Telescope", -- Telescope 명령어 사용 시에만 로드
        keys = {
            { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find Files" },
            { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live Grep" },
            { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Find Buffers" },
            { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help Tags" },
        },
        config = function()
            require('telescope').setup({
                defaults = {
                    -- 성능 최적화
                    file_ignore_patterns = { "node_modules", ".git/", "build/", "*.o", "*.a" },
                }
            })
        end,
    },

    -- 7. 단어 강조 (vim-illuminate)
    {
        "RRethy/vim-illuminate",
        event = { "BufReadPost", "BufNewFile" },
        config = function()
            require("illuminate").configure({
                delay = 50,  -- 더 빠른 반응 (50ms)
                providers = {
                    "lsp",
                    "treesitter",
                    "regex",
                },
                filetypes_denylist = {
                    "dirvish",
                    "fugitive",
                    "nvimtree",
                    "TelescopePrompt",
                },
                min_count_to_highlight = 1, -- 1개 매치부터 강조
                under_cursor = true, -- 커서 위치 단어도 강조
            })
            
            -- 강조 색상 커스터마이징 (onedark 테마에 맞게)
            vim.cmd([=[
              highlight IlluminatedWord cterm=underline gui=underline guibg=#3a3f4b
              highlight IlluminatedCWord cterm=underline gui=underline guibg=#3a3f4b
              highlight IlluminatedWordText cterm=underline gui=underline guibg=#3a3f4b
            ]=])
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
