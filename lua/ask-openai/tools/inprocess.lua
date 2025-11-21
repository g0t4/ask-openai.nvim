local log = require("ask-openai.logs.logger").predictions()
local files = require("ask-openai.helpers.files")
local semantic_grep_module = require("ask-openai.tools.inproc.semantic_grep")
local apply_patch_module = require("ask-openai.tools.inproc.apply_patch")
local plumbing = require("ask-openai.tools.plumbing")
local ansi = require("ask-openai.predictions.ansi")

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

---@param parsed_args table
---@param callback ToolCallDoneCallback
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
            log:luaify_trace("Semantic Grep tool_call query failed: " .. tostring(err), lsp_result)
            result.isError = true
            -- TODO is this how I want to return the error?
            result.error = err.message or "unknown error"
            result.matches = {}
            callback({ result = result })
            return
        end

        if lsp_result.error ~= nil and lsp_result.error ~= "" then
            log:luaify_trace("Semantic Grep tool_call lsp_result error, still calling back: ", lsp_result)
            result.isError = true
            result.matches = lsp_result.matches or {}
            callback({ result = result })
            return
        end

        ---@param lsp_result LSPSemanticGrepResult
        function log_semantic_grep_matches(lsp_result)
            -- TODO move this elsewhere if/when proves useful
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

        -- do not mark isError = false here... that is assumed, might also cause issues if mis-interpreted as an error!
        result.matches = lsp_result.matches
        callback({ result = result }) -- FYI response object sent back to ToolCall/model
    end

    local params = {
        command = "semantic_grep",
        arguments = { semantic_grep_request },
    }

    -- PRN consolidate with other client requests, maybe rag.client?
    _client_request_ids, _cancel_all_requests = vim.lsp.buf_request(0, "workspace/executeCommand", params, on_server_response)
    return _client_request_ids, _cancel_all_requests
end

---@param parsed_args table
---@param callback ToolCallDoneCallback
function semantic_grep_impl(parsed_args, callback)
    M._context_query(parsed_args or "", callback)
end

---@param tool_call table
---@param callback ToolCallDoneCallback
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
    -- TODO try other tools from gptoss repo? (python code runner, browser)

    callback(plumbing.create_tool_call_output_failure("Invalid in-process tool name: " .. name))
end

---@param parsed_args table
---@param callback ToolCallDoneCallback
function M.apply_patch(parsed_args, callback)
    -- GPTOSS has an apply_patch tool it was trained with
    -- instead of bothering with an MCP server, let's just trigger the python script in-process
    -- later I can move this out to another process (MCP server) if that is worthwhile
    callback(plumbing.create_tool_call_output_failure("apply_patch command is not yet connected!!! patience"))
end

return M
