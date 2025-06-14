-- for now, don't try to track external clipboard copies
-- yanked text is way more likely to be relevant

local M = {}

function M.print_yanks()
    local prompt_text = M.get_prompt()
    print(prompt_text)
end

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

local KEEP_TEN_YANKS = 10
M.yanks = {}
function M.on_yank()
    -- ignore if empty
    if vim.v.event.regcontents == nil or #vim.v.event.regcontents == 0 then
        -- TODO what does 0 mean for regcontents?
        -- ignore empty yanks
        return
    end
    if #M.yanks >= KEEP_TEN_YANKS then
        table.remove(M.yanks, 1)
    end
    table.insert(M.yanks, vim.v.event.regcontents)
end

function M.get_context_items()
    if #M.yanks == 0 then
        return {}
    end

    -- PRN should yanks be grouped by file or otherwise?
    local content = "## Recent yanks across all files in the project:\n"
    for _, yank in ipairs(M.yanks) do
        content = content .. table.concat(yank, '\n') .. '\n\n'
    end
    return {
        {
            content = content,
            filename = "nvim-recent-yanks"
        }
    }
end

function M.get_prompt()
    if #M.yanks == 0 then
        return ""
    end

    -- TODO evaluate how to build this part of prompt
    local prompt_text = "## Recent yanks across all files in the project:\n"
    for _, yank in ipairs(M.yanks) do
        prompt_text = prompt_text .. table.concat(yank, '\n') .. '\n\n'
    end

    return prompt_text
end

function M.clear()
    M.yanks = {}
end

function M.setup()
    vim.api.nvim_create_augroup('ContextYank', {})

    vim.api.nvim_create_autocmd("TextYankPost", {
        pattern = '*',
        callback = M.on_yank,
        group = 'ContextYank',
        desc = 'Prediction context yanks'
    })
    vim.api.nvim_create_user_command("AskDumpYanks", M.print_yanks, {})
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
