local M = {}

--- Completion function for slash commands used by user commands.
-- Returns a list of possible completions matching the lead entered.
---@param arglead string The current argument lead typed by the user.
---@param cmdline string The full command line.
---@param cursorpos number The cursor position.
---@return string[] List of matching completions.
function M.SlashCommandCompletion(arglead, cmdline, cursorpos)
    -- Use the public slash command list defined in this module.
    local completions = M.slash_commands or {}
    local result = {}

    -- Escape any pattern magic characters in the lead.
    local escaped = vim.pesc(arglead)
    for _, c in ipairs(completions) do
        if c:find('^' .. escaped) then
            table.insert(result, c)
        end
    end
    return result
end

-- TxChatMessage is used to wrap the generated semantic grep content as a user context message
local TxChatMessage = require("ask-openai.questions.chat.messages.tx")

local function semantic_grep_header_lines(rag_matches)
    return {
        "# Semantic Grep matches: " .. #rag_matches .. "\n",
        "This is automatic context based on my request. These may or may not be relevant."
    }
end

---@param rag_matches LSPRankedMatch[]
---@return TxChatMessage|nil
function M.semantic_grep_user_message(rag_matches)
    if rag_matches == nil or #rag_matches == 0 then
        return nil
    end

    local lines = semantic_grep_header_lines(rag_matches)
    -- TODO! dedupe matches that overlap/touch dedupe.merge_contiguous_rag_chunks()
    vim.iter(rag_matches)
        :each(function(chunk)
            ---@cast chunk LSPRankedMatch
            local file = chunk.file .. ":" .. chunk.start_line_base0 .. "-" .. chunk.end_line_base0
            local code_chunk = chunk.text
            table.insert(lines,
                "## " .. file .. "\n"
                .. code_chunk .. "\n"
            )
        end)
    local content = table.concat(lines, "\n")
    return TxChatMessage:user_context(content)
end

return M
