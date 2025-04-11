-- for now, don't try to track external clipboard copies
-- yanked text is way more likely to be relevant

local M = {}

function M.dump_yank_event()
    print("yanked: " .. vim.inspect(vim.v.event))
    -- yanked: {
    --   inclusive = false,
    --   operator = "y",
    --   regcontents = { '    print("yanked: " .. vim.inspect(vim.v.event))' },
    --   regname = "",
    --   regtype = "V",
    --   visual = false
    -- }
end

M.yanks = {}
function M.on_yank()
    table.insert(M.yanks, vim.v.event.regcontents)
end

function M.setup()
    vim.api.nvim_create_augroup('ContextYank', {})

    vim.api.nvim_create_autocmd("TextYankPost", {
        pattern = '*',
        callback = M.dump_yank_event,
        group = 'ContextYank',
        desc = 'Prediction context yanks'
    })
end

return M

-- :h TextYankPost
-- Just after a |yank| or |deleting| command,
-- but not if the black hole register |quote_| is used nor for |setreg()|.
-- Pattern must be "*".
-- Sets these |v:event| keys:
--     inclusive
--     operator
--     regcontents
--     regname
--     regtype
--     visual
-- The `inclusive` flag combined with the |'[| and |']| marks
-- can be used to calculate the precise region of the operation.
--
-- Non-recursive (event cannot trigger itself).
