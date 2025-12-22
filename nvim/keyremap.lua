-- 키 반복 문제 해결을 위한 추가 설정

-- 방향키를 명시적으로 매핑 (선택사항이지만 도움됨)
-- Normal Mode에서 방향키
vim.keymap.set('n', '<Up>',    'k', { noremap = true })
vim.keymap.set('n', '<Down>',  'j', { noremap = true })
vim.keymap.set('n', '<Left>',  'h', { noremap = true })
vim.keymap.set('n', '<Right>', 'l', { noremap = true })

-- Insert Mode에서도 방향키 동작
vim.keymap.set('i', '<Up>',    '<C-o>k', { noremap = true })
vim.keymap.set('i', '<Down>',  '<C-o>j', { noremap = true })
vim.keymap.set('i', '<Left>',  '<C-o>h', { noremap = true })
vim.keymap.set('i', '<Right>', '<C-o>l', { noremap = true })

-- End key behavior: move to actual end of line
vim.keymap.set('n', '<End>', '$', { noremap = true })
vim.keymap.set('i', '<End>', '<C-o>$', { noremap = true })

-- Home key behavior: move to first non-blank character
vim.keymap.set('n', '<Home>', '^', { noremap = true })
vim.keymap.set('i', '<Home>', '<C-o>^', { noremap = true })
