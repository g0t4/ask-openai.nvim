local M = {}

---@type OpenAITool
M.ToolDefinition = {
    ["function"] = {
        description = "Query RAG for code and documents in the current workspace",
        name = "rag_query",
        parameters = {
            properties = {
                filetype = {
                    type = "string",
                    description = "limit matches to a vim compatible filetype. Leave unset for all filetypes in a workspace."
                },
                query = {
                    type = "string",
                    description = "embeddings query"
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
