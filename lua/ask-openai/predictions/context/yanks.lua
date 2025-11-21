local ContextItem = require("ask-openai.prediction.context.item")
local log = require('ask-openai.logs.logger').predictions()
local messages = require("devtools.messages")

-- for now, don't try to track external clipboard copies
-- yanked text is way more likely to be relevant

-- FYI could also have registers as context?
-- - that might enable me to organize my yanks
-- - also, restore across restarts
-- - hrm... how about "neovim command" output as a context item!
--   I could add these to a file and they get run every time
--   or the file is linked to cases to run it.. interesting
--   then could make one do `:registers` and then bam registers context
--   could toggle these on/off too (one off push :registers command onto the "stack" of these and pop when I'm done with it

local M = {}

M.tracing = false

local function dump_yank_event()
    -- in the case of yanks, knowing when a new yank happens gives a good trace, else I can dump full list anytime too
    if not M.tracing then
        return
    end

    local event = vim.v.event

    vim.schedule(function()
        messages.ensure_open()
        messages.header("Yanking")
        messages.append(current_file_relative_to_workspace_root)
        messages.append(vim.inspect(event))
    end)

    -- yanked: {
    --   inclusive = false, -- use this w/ marks '[ and ]' to find precise location
    --   operator = "y", -- 'd', 'c',
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
    messages.header("Yanks: " .. #M.yanks .. " items")
    messages.append(yanks.content)
end

local MAX_YANKS = 10
M.yanks = {}
function M.on_yank()
    -- PRN send to LS to PURIFY?
    --   AND let it encode the yanks, keep 100 and take top 10 or smth like that?
    --   ALSO, can eliminate similar yanks
    --   AND small ones
    --   etc?

    -- ignore if empty
    current_file_relative_to_workspace_root = vim.fn.expand('%')

    if vim.v.event.regcontents == nil or #vim.v.event.regcontents == 0 then
        -- TODO what does 0 mean for regcontents?
        -- ignore empty yanks
        return
    end
    -- TODO! keep both y and d/c BUT weight y higher than d/c, IOTW when full remove d/cs all first?
    --   or have a recency calculation too?
    if vim.v.event.operator ~= "y" then
        -- "d", "c" for delete/change
        -- PRN do I wanna ignore the others too?
        --  I might want "d" for delete?
        --   or "big" deletes? big changes?
        -- alternative might be to only accept large yanks, not small word replaces or what not
        -- ignore anything other than EXPLICIT yank
        return
    end

    dump_yank_event()

    if #M.yanks >= MAX_YANKS then
        table.remove(M.yanks, 1)
    end
    local yank = {
        -- PRN can I capture line range? or even just current line ... would it help to track operation too (delete vs yank) and pass that along?
        file = current_file_relative_to_workspace_root,
        content = vim.v.event.regcontents,
        operator = vim.v.event.operator,

    }
    table.insert(M.yanks, yank)
end

---@return ContextItem?
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
