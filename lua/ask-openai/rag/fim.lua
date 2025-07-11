local log = require("ask-openai.prediction.logger").predictions()
local files = require("ask-openai.helpers.files")
local M = {}

local cwd = vim.fn.getcwd()
-- only testing ask-openai project currently
local is_rag_indexed_workspace = cwd:find("ask-openai", 1, true) ~= nil

function M.is_rag_supported()
    local current_file = files.get_current_file_relative_path()
    local is_lua = current_file:match("%.lua$")
    if not is_lua then
        log:info("skipping RAG for non-lua files: " .. current_file)
        return false
    end

    return is_rag_indexed_workspace
end

local function fim_concat(prefix, suffix, limit)
    limit = limit or 1500 -- 2000?
    local half = math.floor(limit / 2)

    local short_prefix = prefix:sub(-half)
    local short_suffix = suffix:sub(1, half)

    return short_prefix .. "\n<<<FIM>>>\n" .. short_suffix
end

function M.query_rag_via_lsp(document_prefix, document_suffix, callback)
    local query = fim_concat(document_prefix, document_suffix)

    local message = {
        text = query,
        current_file_absolute_path = files.get_current_file_absolute_path(),
    }

    local _client_request_ids, _cancel_all_requests = vim.lsp.buf_request(0, "workspace/executeCommand", {
        command = "context.fim.query",
        -- arguments is an array table, not a dict type table (IOTW only keys are sent if you send a k/v map)
        arguments = { message },
    }, function(err, result)
        if err then
            vim.notify("RAG query failed: " .. err.message, vim.log.levels.ERROR)
            return
        end

        log:info("RAG matches (client):", vim.inspect(result))
        local rag_matches = result.matches or {}
        callback(rag_matches)
    end)
    return _client_request_ids, _cancel_all_requests
end

return M
