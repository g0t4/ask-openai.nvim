local messages = require("devtools.messages")
local ctags = require("ask-openai.prediction.context.ctags")
local log = require("ask-openai.prediction.logger").predictions()
local ContextItem = require("ask-openai.prediction.context.item")

-- TODO what about context based on the current statement/expression...
--   like if I type ChatMessage... go get the class for me (its whole file) and include that?!
--   do the same for all matching symbols so if I do Chat<PAUSE> then get ChatThread and ChatMessage

local M = {}

---@return ParsedTagLine[] tag_lines
function M.filter_ctags_by_word(word)
    local tags = ctags.parsed_tag_lines_for_this_workspace(ctags.get_language_for_current_buffer())
    local devtools_tags = ctags.parsed_tag_lines_for_lua_devtools()
    tags = vim.list_extend(tags, devtools_tags)
    local filtered_tags = {}
    for _, tag in ipairs(tags) do
        if tag.tag_name:find(word, 1, true) then
            table.insert(filtered_tags, tag)
        end
    end
    -- TODO also match on filename? that means the full file is included b/c every entry would match
    --  but, if you type local messages => would give require("...")
    return filtered_tags
end

---@return ContextItem? item
function M.get_context_item()
    -- TODO return multiple context items, one per tag file (per project/workspace?)
    -- TODO check if current line is empty? abort before even trying then?
    local word = vim.fn.expand("<cword>")
    --
    -- if empty, then get word before
    if word == "" or word == nil then
        log:info("did not find word, trying before cursor...")
        -- word = vim.fn.expand("<cWORD>")
        local col = vim.fn.col('.') - 1
        local line = vim.fn.getline('.')
        local before_cursor = line:sub(1, col)
        word = before_cursor:match("([%w_]+)$")
    end
    if word == nil then
        -- TODO OR should I just return full ctags on empty lines?
        -- i.e. on a neww line, nothing's gonna match!
        log:info("no word at cursor, or before... skipping matching_ctags")
        return nil
    end
    -- PRN also <cWORD> ? match either?! perhaps if under a token budge?

    return M.get_context_item_for(word)
end

function M._require_for_file_path(file_path)
    -- strip leading lua
    file_path = file_path:gsub("^lua/", "")
    -- strip trailing .lua
    file_path = file_path:gsub("%.lua$", "")
    -- replace / with .
    file_path = file_path:gsub("/", ".")
    return string.format("require('%s')", file_path)
end

---@return ContextItem? item
function M.get_context_item_for(word)
    local matches = M.filter_ctags_by_word(word)
    -- TODO! instead of file path, how about turn it into a require call!
    local reassembled_content = ctags.reassemble_tags(matches, M._require_for_file_path)
    return ContextItem:new(reassembled_content, "tags")
end

function M.dump_this()
    local context = M.get_context_item()
    messages.ensure_open()
    messages.append(context.content)
end

function M.setup()
    vim.api.nvim_create_user_command("AskDumpMatchingCTags", M.dump_this, {})
end

return M
