local log = require("ask-openai.logs.logger").predictions()
local files = require("ask-openai.helpers.files")
local semantic_grep_module = require("ask-openai.tools.inproc.semantic_grep")
local apply_patch_module = require("ask-openai.tools.inproc.apply_patch")

local M = {}

---@type OpenAITool[]
M.tools_available = {
    semantic_grep = semantic_grep_module.ToolDefinition
    -- apply_patch = apply_patch_module.ToolDefinition -- TODO
}

---@param tool_name string
---@return boolean
function M.handles_tool(tool_name)
    local tool = M.tools_available[tool_name]
    return tool ~= nil
end

function M._context_query(parsed_args, callback)
    local languages = ""
    if not parsed_args.filetype then
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


    ---@param lsp_result LSPSemanticGrepResult
    function on_server_response(err, lsp_result)
        local result = {}
        if err then
            -- vim.notify("Semantic Grep tool_call query failed: " .. err.message, vim.log.levels.ERROR)
            log:error("Semantic Grep tool_call query failed: " .. tostring(err), vim.inspect(lsp_result))
            result.isError = true
            -- TODO is this how I want to return the error?
            result.error = err.message or "unknown error"
            result.matches = {}
            callback({ result = result })
            return
        end

        if lsp_result.error ~= nil and lsp_result.error ~= "" then
            log:error("Semantic Grep tool_call response error, still calling back: ", vim.inspect(lsp_result))
            result.isError = true
            result.matches = lsp_result.matches or {}
            callback({ result = result })
            return
        end

        log:info("Semantic Grep tool_call matches (client):", vim.inspect(lsp_result))
        -- do not mark isError = false here... that is assumed, might also cause issues if mis-interpreted as an error!
        result.matches = lsp_result.matches
        callback({ result = result })
    end

    local params = {
        command = "semantic_grep",
        arguments = { semantic_grep_request },
    }

    -- PRN consolidate with other client requests, maybe rag.client?
    _client_request_ids, _cancel_all_requests = vim.lsp.buf_request(0, "workspace/executeCommand", params, on_server_response)
    return _client_request_ids, _cancel_all_requests
end

function semantic_grep_impl(parsed_args, callback)
    M._context_query(parsed_args or "", callback)
end

---@param tool_call table
---@param callback fun(response: table)
function M.send_tool_call(tool_call, callback)
    local name = tool_call["function"].name

    if name == "semantic_grep" then
        local args = tool_call["function"].arguments
        local parsed_args = vim.json.decode(args)
        semantic_grep_impl(parsed_args, callback)
        return
    elseif name == "apply_patch" then
        local args = tool_call["function"].arguments
        local parsed_args = vim.json.decode(args)
        M.apply_patch(parsed_args, callback)
        return
    end

    error("in-process tool not implemented yet: " .. name)
end

---@param parsed_args table
---@param callback fun(response: table)
function M.apply_patch(parsed_args, callback)
    -- GPTOSS has an apply_patch tool it was trained with
    -- instead of bothering with an MCP server, let's just trigger the python script in-process
    -- later I can move this out to another process (MCP server) if that is worthwhile
    error("apply_patch not implemented")
end

return M
