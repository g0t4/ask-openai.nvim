local log = require("devtools.logs.logger").universal()
local M = {}

-- TxChatMessage is used to wrap the generated semantic grep content as a user context message
local TxChatMessage = require("ask-openai.agents.messages.tx")

---@param rag_matches LSPRankedMatch[]
---@return string?
function M.explain_rag_auto_context(rag_matches)
    if #rag_matches == 0 then return end
    return M.matches_to_markdown(rag_matches, "This is automatic context based on my request. These may not be relevant to my request.")
end

---@param messages {}
---@param rag_matches LSPRankedMatch[]
function M.add_auto_user_message(messages, rag_matches)
    M.add_user_message(messages, M.explain_rag_auto_context(rag_matches))
end

---@param messages {}
---@param rag_matches_markdown? string
function M.add_user_message(messages, rag_matches_markdown)
    if rag_matches_markdown == nil then return end
    table.insert(messages, TxChatMessage:user_context(rag_matches_markdown))
end

---@param matches LSPRankedMatch[]
---@param explanation string? -- extra details to insert after header with count of matches
---@return string
function M.matches_to_markdown(matches, explanation)
    -- TODO! dedupe matches that overlap/touch dedupe.merge_contiguous_rag_chunks()
    local lines = {
        "# Semantic Grep matches: " .. #matches,
        "",
    }

    if explanation ~= nil and explanation ~= "" then
        table.insert(lines, explanation)
        table.insert(lines, "")
    end

    for _, match in ipairs(matches) do
        local function build_position_string(match)
            local parts = { match.start_line_base0 + 1 }
            if match.start_column_base0 and match.start_column_base0 > 0 then
                table.insert(parts, ":" .. (match.start_column_base0 + 1))
            end
            table.insert(parts, "-")
            table.insert(parts, match.end_line_base0 + 1)
            if match.end_column_base0 and match.end_column_base0 > 0 then
                table.insert(parts, ":" .. (match.end_column_base0 + 1))
            end
            return table.concat(parts, "")
        end

        local position = build_position_string(match)



        local file = match.file .. ":" .. position
        local text = match.text

        -- * add leading whitespace for non-zero start columns (ts chunks only, so far)

        -- table.insert(lines, "## " .. file .. "\n" .. text .. "\n")

        extension = vim.fn.fnamemodify(match.file, ":e")

        -- try formatting as fenced markdown code blocks inside of an h2 header with match counter...
        -- which means we can syntax highlight the inline code!
        -- otherwise I'd say lets leave it without formatting which would be fine too
        vim.list_extend(lines, {
            "## " .. file ..
            "",
            -- benefit of using valid fence indicator with only the file extension => inline formatting is working now in my nvim live trace viewer!
            --  and I keep the header with the full file name + positions (start line + start col)
            "```" .. extension,
            text,
            "```",
            "",
        })
    end
    local markdown = table.concat(lines, "\n")
    return markdown
end

return M
