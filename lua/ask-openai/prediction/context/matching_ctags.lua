local ctags = require("ask-openai.prediction.context.ctags")
-- TODO what about context based on the current statement/expression...
--   like if I type ChatMessage... go get the class for me (its whole file) and include that?!
--   do the same for all matching symbols so if I do Chat<PAUSE> then get ChatThread and ChatMessage

local M = {}

function M.filter_ctags_by_word(word)
    local tags = ctags.all_reassembled_lua_tags()
    local filtered_tags = {}
    for _, tag in ipairs(tags) do
        if tag.tag_name:match(word) then
            table.insert(filtered_tags, tag)
        end
    end
    return filtered_tags
end

function M.get_filtered_ctags()
    local word = vim.api.nvim_get_current_word()
    return M.filter_ctags_by_word(word)
end

function M.get_context_item()
    return M.get_filtered_ctags()
end

function M.dump_this()
    return M.get_context_item()
end

function M.setup()
    vim.api.nvim_create_user_command("AskDumpMatchingCTags", M.dump_this, {})
end

return M
