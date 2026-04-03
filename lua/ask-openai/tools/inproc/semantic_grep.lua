local log = require("ask-openai.logs.logger").predictions()
local ansi = require("ask-openai.predictions.ansi")
local client = require("ask-openai.rag.client.client")

local M = {
    ---@type OpenAITool;
    ToolDefinition = {
        ["function"] = {
            description =
            "Retrieval tool (the R in RAG) for code and documents in the current workspace. Uses a vector store with embeddings of the entire codebase. And a re-ranker for sorting results.",
            name = "semantic_grep",
            parameters = {
                properties = {
                    filetype = {
                        type = "string",
                        description = "limit matches to a vim compatible filetype. default includes all filetypes"
                    },
                    query = {
                        type = "string",
                        description = "query text, what you are looking for"
                    },
                    instruct = {
                        type = "string",
                        description = "instructions for the query, explain the type of query"
                    },
                    top_k = {
                        type = "number",
                        description = "number of matches to return (post reranking)"
                    },
                    embed_top_k = {
                        type = "number",
                        description = "number of embeddings matches to consider for reranking"
                    },
                },
                required = { "query" },
                type = "object"
            }
        },
        type = "function"
    }
}

---@param parsed_args table
---@param callback ToolCallDoneCallback
function M.call(parsed_args, callback)
    local languages = ""
    -- log:info("parsed_args", vim.inspect(parsed_args))
    if parsed_args.filetype == nil or parsed_args.filetype:match("^%s*$") then
        -- PRN use EVERYTHING instead of GLOBAL?
        -- when using tools that might make more sense
        -- but for now, assume if I limit the list then I did that for a good reason that likely benefits agent tool use
        languages = "GLOBAL" -- GLOBAL is subject to rag.yaml -> global_languages
    end

    ---@type LSPSemanticGrepRequest
    local semantic_grep_request = {
        query = parsed_args.query,
        instruct = parsed_args.instruct or "Find relevant code for the AI agent's query",
        -- TODO make currentFileAbsolutePath nil-able instead of empty string
        currentFileAbsolutePath = "",
        -- TODO NEED TO make sure no issues using filetype vs extension....
        vimFiletype = parsed_args.filetype,
        languages = languages,
        skipSameFile = false,
        topK = parsed_args.top_k or 5,
        embedTopK = parsed_args.embed_top_k or 18,
    }

    client.semantic_grep_with_timeout(semantic_grep_request, callback)
end

return M
