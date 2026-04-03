local log = require("ask-openai.logs.logger").predictions()
local ansi = require("ask-openai.predictions.ansi")

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

    M.semantic_grep_with_timeout(semantic_grep_request, callback)
end

--- Executes a semantic grep request with:
--- - check server is available
--- - supports timeout
---@param semantic_grep_request LSPSemanticGrepRequest
---@param callback fun(result: table) -- called with the result or error
---@return nil
function M.semantic_grep_with_timeout(semantic_grep_request, callback)
    --   TODO!!! wire new client into other lua semantic_grep executeCommand usages

    log:info("semantic_grep_request", vim.inspect(semantic_grep_request))

    -- normally I'd move closer to first use, but for this LSP cancel scenario, sometimes a nested func wants to use these (with nil check) and I forget about these... so leave here so it is obvious I can use them anywhere if check happens
    local _client_request_ids, _cancel_all_requests, _request_timeout_timer

    ---@param message string
    ---@param matches? table optional list of matches to include in the error payload
    -- Invokes the provided callback with a standardized error payload.
    -- The function name is chosen to better convey its purpose.
    local function error_response(message, matches)
        matches = matches or {}
        callback({
            result = {
                isError = true,
                error = message,
                matches = matches,
            },
        })
    end

    ---@param lsp_result LSPSemanticGrepResult
    local function on_language_server_response(err, lsp_result)
        if err then
            -- IIGC this is a client side error in making the request?
            log:luaify_trace("Semantic Grep tool_call query failed (callback err): " .. vim.inspect(err), lsp_result)
            error_response(err.message or "unknown error")
            return
        end

        if lsp_result.error ~= nil and lsp_result.error ~= "" then
            -- Language Server errors (returned successfully) hit this pathway
            log:luaify_trace("Semantic Grep tool_call lsp_result error, still calling back: ", lsp_result)
            error_response(lsp_result.error, lsp_result.matches)
            return
        end

        ---@param lsp_result LSPSemanticGrepResult
        function log_semantic_grep_matches(lsp_result)
            log:trace("Semantic Grep tool_call matches (client):")
            vim.iter(lsp_result.matches)
                :each(
                ---@param m LSPRankedMatch
                    function(m)
                        local line_range = tostring(m.start_line_base0 + 1) .. "-" .. (m.end_line_base0 + 1)
                        local header = ansi.yellow(tostring(m.file) .. ":" .. line_range .. "\n")
                        log:trace(header, m.text)
                    end
                )
        end

        -- log_semantic_grep_matches(lsp_result)

        callback({
            result = {
                -- do not mark isError = false here... that is assumed, might also cause issues if mis-interpreted as an error!
                matches = lsp_result.matches
            }
        })
    end

    local params = {
        command = "semantic_grep",
        arguments = { semantic_grep_request },
    }

    if not vim.lsp.get_clients({ name = "ask_language_server", bufnr = 0 })[1] then
        log:error("ask_language_server is not available")
        error_response("Semantic Grep aborted... ask_language_server is not available")
        return
    end

    _client_request_ids, _cancel_all_requests = vim.lsp.buf_request(0, "workspace/executeCommand", params, function(err, result, ctx, config)
        if _request_timeout_timer then
            _request_timeout_timer:stop()
        end
        on_language_server_response(err, result, ctx, config)
    end)

    local timeout_ms = 5000
    _request_timeout_timer = vim.defer_fn(function()
        log:info("Semantic Grep request timed out")
        error_response("Semantic Grep request timed out")
        vim.lsp.cancel_request(0, _client_request_ids) -- IIUC same as using _cancel_all_requests()?
    end, timeout_ms)
end

return M
