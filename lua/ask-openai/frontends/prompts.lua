local M = {}

local function semantic_grep_header_lines(rag_matches)
    return {
        "# Semantic Grep matches: " .. #rag_matches .. "\n",
        "This is automatic context based on my request. These may or may not be relevant."
    }
end

function M.semantic_grep_user_message_text(rag_matches)
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
    return table.concat(lines, "\n")
end

return M
