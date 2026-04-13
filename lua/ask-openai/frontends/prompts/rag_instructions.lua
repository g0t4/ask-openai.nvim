local log = require("ask-openai.logs.logger").predictions()
local M = {}

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

            -- * add leading whitespace for non-zero start columns (ts chunks only, so far)
            local start_col0 = chunk.start_column_base0
            if start_col0 and start_col0 > 0 then
                -- I noticed in some cases a treesitter matched function has non-zero start column and that shows as incorrectly indented in thread RAG matches
                --   mostly wanted to avoid model being confused, especialy if multiple matches are from same file and the de-indented func signature (often all that is off like this)... is just slightly wrong but could it confuse the generated code?
                --      could this be partially why I get poorly indented suggestions at times?
                --   so, I am adding whitespace for now
                --   FYI it would be fine to roll this back, most of the time it would just be incorrectly indented function signature, which isn't even invalid in python
                -- TODO any material cases where the leading chars aren't actually whitespace?
                local visible_ws = " "
                code_chunk = string.rep(visible_ws, start_col0) .. code_chunk
                -- TODO consider is col offset in bytes or chars? (see RAG preview for more on this)... i.e. with emoji or other unicode chars?
            end

            table.insert(lines,
                "## " .. file .. "\n"
                .. code_chunk .. "\n"
            )
        end)
    local content = table.concat(lines, "\n")
    return TxChatMessage:user_context(content)
end

return M
