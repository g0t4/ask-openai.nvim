local log = require("ask-openai.logs.logger").predictions()
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

function M.is_rag_supported_in_current_file()
    if not M.is_rag_indexed_workspace then
        return false
    end

    local current_file_extension = vim.fn.expand("%:e")
    return vim.tbl_contains(M.rag_extensions, current_file_extension)
end

local function fim_concat(prefix, suffix, limit)
    limit = limit or 1500 -- 2000?
    local half = math.floor(limit / 2)

    -- * warnings so I can investigate
    --   FYI I think I will just supress these warnings b/c a limit is fine for RAG that is far less than FIM limits
    --   FYI IT IS OK TO REMOVE THE WARNINGS! OR COMMENT THEM OUT! or set at debug log level
    if prefix:len() > half then
        log:warn(
            "FIM prefix is too long FOR RAG and will be truncated. limit is: " .. limit .. ". prefix length is: " .. prefix:len()
        )
    end
    if suffix:len() > half then
        log:warn(
            "FIM suffix is too long FOR RAG and will be truncated. limit is: " .. limit .. ". suffix length is: " .. suffix:len()
        )
    end

    local short_prefix = prefix:sub(-half) -- take from the end of the prefix (if over limit)
    local short_suffix = suffix:sub(1, half) -- take from the start of the suffix (if over limit)

    return short_prefix .. "<<<FIM>>>" .. short_suffix
end

---@class LSPRagQueryMessage
---@field text string
---@field vim_filetype string
---@field current_file_absolute_path string
---@field instruct string
_G.LSPRagQueryMessage = {}


---@class LSPRagQueryResult
---@field matches LSPRankedMatch[]
_G.LSPRagQueryResult = {}


---@class LSPRankedMatch
---@field text string
---@field file string
---@field start_line_base0 integer
---@field start_column_base0 integer
---@field end_line_base0 integer
---@field end_column_base0 integer|nil
---@field type string
---@field score number
---@field rank integer
---@field signature string
_G.LSPRankedMatch = {}

---@param user_prompt string
---@param code_context string
---@param callback fun(matches: LSPRankedMatch[])
function M.context_query_rewrites(user_prompt, code_context, callback)
    -- FYI use user message for now as Instruct and selected code as the Query
    -- local rewrite_instruct = "Modify the code as requested"
    local query = code_context
    local instruct = user_prompt
    return M._context_query(query, instruct, callback)
end

---@param document_prefix string
---@param document_suffix string
---@param callback fun(matches: LSPRankedMatch[])
function M.context_query_fim(document_prefix, document_suffix, callback)
    local fim_specific_instruct = "Complete the missing portion of code (FIM) based on the surrounding context (Fill-in-the-middle)"
    local query = fim_concat(document_prefix, document_suffix)
    return M._context_query(query, fim_specific_instruct, callback)
end

---@param query string
---@param instruct string
---@param callback fun(matches: LSPRankedMatch[])
function M._context_query(query, instruct, callback)
    ---@type LSPRagQueryMessage
    local message = {
        text = query,
        instruct = instruct, -- let the server side handle whether or not to include instructions and errors
        current_file_absolute_path = files.get_current_file_absolute_path(),
        vim_filetype = vim.bo.filetype,
    }

    local _client_request_ids, _cancel_all_requests = vim.lsp.buf_request(0, "workspace/executeCommand", {
            command = "context.query",
            -- arguments is an array table, not a dict type table (IOTW only keys are sent if you send a k/v map)
            arguments = { message },
        },
        ---@param result LSPRagQueryResult
        function(err, result)
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
