local ContextItem = require("ask-openai.prediction.context.item")
local log = require('ask-openai.prediction.logger').predictions()
local messages = require("devtools.messages")

-- for now, don't try to track external clipboard copies
-- yanked text is way more likely to be relevant

local M = {}

local function dump_yank_event()
    log:info("yanked: " .. vim.inspect(vim.v.event))
    -- yanked: {
    --   inclusive = false,
    --   operator = "y",
    --   regcontents = { '    print("yanked: " .. vim.inspect(vim.v.event))' },
    --   regname = "",
    --   regtype = "V",
    --   visual = false
    -- }
end

function M.dump_yanks()
    local yanks = M.get_context_item()
    if not yanks then
        vim.print("nothing yanked")
        return
    end
    log:info("yanks:\n" .. yanks.content)
    messages.ensure_open()
    messages.header("Recent Yanks")
    messages.append(yanks.content)
end

local MAX_YANKS = 10
M.yanks = {}
function M.on_yank()
    -- dump_yank_event()
    -- ignore if empty
    event = vim.v.event
    current_file_relative_to_workspace_root = vim.fn.expand('%')

    vim.schedule(function()
        messages.ensure_open()
        messages.header("Yanking")
        messages.append(current_file_relative_to_workspace_root)
        messages.append(vim.inspect(event))
    end)

    if vim.v.event.regcontents == nil or #vim.v.event.regcontents == 0 then
        -- TODO what does 0 mean for regcontents?
        -- ignore empty yanks
        return
    end
    if #M.yanks >= MAX_YANKS then
        table.remove(M.yanks, 1)
    end
    local yank = {
        -- PRN can I capture line range? or even just current line ... would it help to track operation too (delete vs yank) and pass that along?
        file = current_file_relative_to_workspace_root,
        content = vim.v.event.regcontents
    }
    table.insert(M.yanks, yank)
end

--- @return ContextItem?
function M.get_context_item()
    if #M.yanks == 0 then
        return nil
    end

    -- PRN should yanks be grouped by file or otherwise?
    local content = "## Recent yanks across all files in the project:\n"
    for _, yank in ipairs(M.yanks) do
        -- TODO! pass back chunk objects and let fim builder do this
        content = content ..
            ".. yanked from " .. yank.file .. ":\n" ..
            table.concat(yank.content, '\n') .. '\n\n'
    end
    return ContextItem:new(content, "nvim-recent-yanks.txt")
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
    vim.api.nvim_create_user_command("AskDumpYanks", M.dump_yanks, {})
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
