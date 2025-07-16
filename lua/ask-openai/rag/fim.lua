local log = require("ask-openai.prediction.logger").predictions()
local files = require("ask-openai.helpers.files")
local M = {}

local function check_supported_dirs()
    local cwd = vim.fn.getcwd()
    dot_rag_dir = cwd .. "/.rag"

    M.is_rag_indexed_workspace = files.exists(dot_rag_dir)

    if not M.is_rag_indexed_workspace then
        log:info("RAG is disabled b/c there is NO .rag dir: " .. dot_rag_dir)
        return
    end

    M.rag_extensions = files.list_directories(dot_rag_dir)
    log:info("RAG is supported for: " .. vim.inspect(M.rag_extensions))
end
check_supported_dirs()

function M.is_rag_supported()
    if not M.is_rag_indexed_workspace then
        return false
    end

    local current_file_extension = vim.fn.expand("%:e")
    return vim.tbl_contains(M.rag_extensions, current_file_extension)
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
