local M = {}

function M.semantic_grep_header(rag_matches)
    return {
        "# Semantic Grep matches: " .. #rag_matches .. "\n",
        "This is automatic context based on my request. These may or may not be relevant."
    }
end

return M
