local M = {}

function M.semantic_grep_header(rag_matches)
    return {
        "# Semantic Grep matches: " .. #rag_matches .. "\n",
        "This is automatic context from my neovim AI tools. The user's request is used to query for relevant code. Only the top results are included. These may or may not be relevant."
    }
end

return M
