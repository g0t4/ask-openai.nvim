local M = {}

---@type OpenAITool
M.ToolDefinition = {
    ["function"] = {
        description = "Retrieval tool (the R in RAG) for code and documents in the current workspace. Uses a vector store with embeddings of the entire codebase. And a re-ranker for sorting results.",
        name = "semantic_grep",
        parameters = {
            properties = {
                filetype = {
                    type = "string",
                    description = "limit matches to a vim compatible filetype. Leave unset for all indexed filetypes in a workspace."
                },
                query = {
                    type = "string",
                    description = "query text, what you are looking for"
                },
                instruct = {
                    type = "string",
                    description = "instructions for the query"
                },
                top_k = {
                    type = "number",
                    description = "number of results to return (post reranking)"
                },
                embed_top_k = {
                    type = "number",
                    description = "number of embeddings to consider for reranking"
                },
            },
            required = { "query" },
            type = "object"
        }
    },
    type = "function"
}

-- TODO move functions too?

return M
