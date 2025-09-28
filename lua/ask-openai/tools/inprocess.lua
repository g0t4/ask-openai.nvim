local log = require("ask-openai.logs.logger").predictions()
local files = require("ask-openai.helpers.files")

local M = {}

---@class ToolDefinition
---@field name string
---@field description string
---@field inputSchema table
M.tools_available = {
    ---@type ToolDefinition
    rag_query = {
        ["function"] = {
            description = "Query RAG for code and documents in the current workspace",
            name = "rag_query",
            parameters = {
                properties = {
                    -- TODO multiple filetypes?
                    filetype = {
                        type = "string",
                        description = "(optional) limit matches to a vim compatible filetype. Leave unset for all filetypes in a workspace."
                    },
                    query = {
                        type = "string",
                        description = "The query to send to the RAG system"
                    },
                    instruct = {
                        type = "string",
                        description = "Optional instruct to provide context for the query"
                    },
                    top_k = {
                        type = "number",
                        description = "Top K results to return"
                    },
                    embed_top_k = {
                        type = "number",
                        description = "Number of embeddings to consider for reranking"
                    },
                },
                required = { "query" },
                type = "object"
            }
        },
        type = "function"
    }
}


---@param tool_name string
---@return boolean
function M.handles_tool(tool_name)
    local tool = M.tools_available[tool_name]
    return tool ~= nil
end

function M._context_query(parsed_args, callback)
    ---@type LSPRagQueryRequest
    local lsp_rag_request = {
        query = parsed_args.query,
        instruct = parsed_args.instruct or "",
        -- TODO make currentFileAbsolutePath nil-able instead of empty string
        currentFileAbsolutePath = "",
        -- TODO NEED TO make sure no issues using filetype vs extension....
        vimFiletype = parsed_args.filetype,
        -- FYI right now backend only uses languages for ALL scenario, not sure why I did that
        languages = parsed_args.filetype or "ALL", -- ALL languages if no filetype requested
        skipSameFile = false,
        topK = parsed_args.top_k or 5,
        embedTopK = parsed_args.embed_top_k or 18,
    }

    local _client_request_ids, _cancel_all_requests

    -- ** error example from run_command
    -- "result": {
    --   "isError": true,
    --   "content": [
    --     {
    --       "type": "text",
    --       "text": "Command failed: lds\n/bin/sh: lds: command not found\n",
    --       "name": "ERROR"
    --     },
    --     {
    --       "type": "text",
    --       "text": "/bin/sh: lds: command not found\n",
    --       "name": "STDERR"
    --     }
    --   ]
    -- },

    --  ** happy path from run_command:
    --  {
    --   "result": {
    --     "content": [
    --       {
    --         "type": "text",
    --         "text": "a.out\nis-this-my-fault.log\nlua\nlua_modules\nMakefile\nnotes\npyproject.toml\nREADME.md\nstart-rag-server.fish\ntags\ntests\ntmp\nuv.lock\nvenv-fix-buil21.fish\n",
    --         "name": "STDOUT"
    --       }
    --     ]
    --   },
    --   "jsonrpc": "2.0",
    --   "id": 1
    -- }               --
    --


    ---@param result LSPRagQueryResult
    function on_server_response(err, lsp_result)
        local result = {}
        if err then
            -- vim.notify("RAG tool_call query failed: " .. err.message, vim.log.levels.ERROR)
            log:error("RAG tool_call query failed: " .. tostring(err), vim.inspect(lsp_result))
            result.isError = true
            -- TODO is this how I want to return the error?
            result.error = err.message or "unknown error"
            result.matches = {}
            callback({ result = result })
            return
        end

        if lsp_result.error ~= nil and lsp_result.error ~= "" then
            log:error("RAG tool_call response error, still calling back: ", vim.inspect(lsp_result))
            result.isError = true
            result.matches = lsp_result.matches or {}
            callback({ result = result })
            return
        end

        log:info("RAG tool_call matches (client):", vim.inspect(lsp_result))
        -- do not mark isError = false here... that is assumed, might also cause issues if mis-interpreted as an error!
        result.matches = lsp_result.matches
        callback({ result = result })
    end

    local params = {
        command = "rag_query",
        arguments = { lsp_rag_request },
    }

    -- PRN consolidate with other client requests, maybe rag.client?
    _client_request_ids, _cancel_all_requests = vim.lsp.buf_request(0, "workspace/executeCommand", params, on_server_response)
    return _client_request_ids, _cancel_all_requests
end

function rag_query_impl(parsed_args, callback)
    M._context_query(parsed_args or "", callback)
end

---@param tool_call table
---@param callback fun(response: table)
function M.send_tool_call(tool_call, callback)
    local name = tool_call["function"].name

    if name == "rag_query" then
        local args = tool_call["function"].arguments
        local parsed_args = vim.json.decode(args)
        rag_query_impl(parsed_args, callback)
        return
    end

    error("in-process tool not implemented yet: " .. name)
end

return M
