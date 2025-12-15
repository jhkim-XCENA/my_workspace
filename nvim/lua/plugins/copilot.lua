-- lua/plugins/copilot.lua
-- GitHub Copilot 통합 설정 (고립된 모듈)
-- 이 파일만 수정하여 Copilot 기능을 업데이트할 수 있습니다.

return {
    -- 1. Copilot Core (Lua 버전)
    {
        "zbirenbaum/copilot.lua",
        cmd = "Copilot",
        event = "InsertEnter", -- 입력 모드 진입 시 로드 (시작 속도 최적화)
        config = function()
            require("copilot").setup({
                suggestion = { 
                    enabled = true,
                    auto_trigger = true, -- 입력 시 자동으로 제안 표시
                    debounce = 75,       -- 제안 딜레이 (ms)
                    keymap = {
                        accept = "<C-l>",      -- Ctrl+l 로 제안 수락
                        accept_word = false,   -- 단어 단위 수락 비활성화
                        accept_line = false,   -- 라인 단위 수락 비활성화
                        next = "<C-j>",        -- 다음 제안
                        prev = "<C-k>",        -- 이전 제안
                        dismiss = "<C-h>",     -- 제안 무시
                    },
                },
                panel = { enabled = false }, -- 패널 기능 비활성화 (Chat으로 대체)
                filetypes = {
                    yaml = false,
                    markdown = false,
                    help = false,
                    gitcommit = false,
                    gitrebase = false,
                    hgcommit = false,
                    svn = false,
                    cvs = false,
                    ["."] = false,
                },
            })
        end,
    },

    -- 2. nvim-cmp와 Copilot 통합 (자동완성 목록에 Copilot 표시)
    {
        "zbirenbaum/copilot-cmp",
        dependencies = { "zbirenbaum/copilot.lua" },
        config = function()
            require("copilot_cmp").setup()
        end,
    },

    -- 3. Copilot Chat (채팅 기능)
    {
        "CopilotC-Nvim/CopilotChat.nvim",
        branch = "main", -- 최신 기능 사용
        cmd = {
            "CopilotChat",
            "CopilotChatOpen",
            "CopilotChatClose",
            "CopilotChatToggle",
            "CopilotChatExplain",
            "CopilotChatFix",
            "CopilotChatOptimize",
            "CopilotChatReview",
            "CopilotChatTests",
            "CopilotChatDocs",
        },
        dependencies = {
            { "zbirenbaum/copilot.lua" },
            { "nvim-lua/plenary.nvim" },
        },
        build = "make tiktoken", -- MacOS/Linux에서 응답 속도 향상 (선택)
        opts = {
            debug = false,
            show_help = "yes",
            prompts = {
                Explain = "선택한 코드를 한국어로 설명해주세요.",
                Review = "선택한 코드를 리뷰해주세요. 개선점을 한국어로 제안해주세요.",
                Fix = "선택한 코드의 버그를 수정해주세요.",
                Optimize = "선택한 코드를 성능 최적화해주세요.",
                Docs = "선택한 코드에 문서화 주석을 추가해주세요.",
                Tests = "선택한 코드에 대한 테스트 코드를 작성해주세요.",
            },
        },
        keys = {
            -- 채팅 토글
            { 
                "<leader>cc", 
                ":CopilotChatToggle<CR>", 
                desc = "Copilot Chat 토글",
                mode = { "n", "v" }
            },
            -- 코드 설명
            { 
                "<leader>ce", 
                ":CopilotChatExplain<CR>", 
                desc = "코드 설명",
                mode = "v"
            },
            -- 코드 수정
            { 
                "<leader>cf", 
                ":CopilotChatFix<CR>", 
                desc = "코드 수정",
                mode = "v"
            },
            -- 코드 최적화
            { 
                "<leader>co", 
                ":CopilotChatOptimize<CR>", 
                desc = "코드 최적화",
                mode = "v"
            },
            -- 코드 리뷰
            { 
                "<leader>cr", 
                ":CopilotChatReview<CR>", 
                desc = "코드 리뷰",
                mode = "v"
            },
            -- 테스트 생성
            { 
                "<leader>ct", 
                ":CopilotChatTests<CR>", 
                desc = "테스트 생성",
                mode = "v"
            },
            -- 문서화
            { 
                "<leader>cd", 
                ":CopilotChatDocs<CR>", 
                desc = "문서 생성",
                mode = "v"
            },
        },
        config = function(_, opts)
            local chat = require("CopilotChat")
            chat.setup(opts)

            -- 채팅 윈도우 스타일 설정
            vim.api.nvim_create_autocmd("BufEnter", {
                pattern = "copilot-*",
                callback = function()
                    vim.opt_local.relativenumber = false
                    vim.opt_local.number = false
                end,
            })
        end,
    },
}
