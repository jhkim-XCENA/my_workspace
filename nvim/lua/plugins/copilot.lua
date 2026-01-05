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
                    debounce = 30,       -- 제안 딜레이를 30ms로 단축 (50에서 개선)
                    min_prefix_length = 0, -- 입력 없어도 바로 제안 표시
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

    -- 3. Copilot Chat (채팅 기능) - 비활성화
    -- {
    --     "CopilotC-Nvim/CopilotChat.nvim",
    --     enabled = false,
    -- },
}


