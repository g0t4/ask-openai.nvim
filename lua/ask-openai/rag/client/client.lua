local ansi = require("devtools.ansi")
local log = require("devtools.logs.logger").universal()

local M = {}

--- Checks if a given LSP client is attached to the current buffer.
--- @param lsp_buffer_number? integer
--- @return boolean
function M.is_lsp_client_available(lsp_buffer_number)
    lsp_buffer_number = lsp_buffer_number or 0
    local clients = vim.lsp.get_clients({ name = "ask_language_server", bufnr = lsp_buffer_number })
    return clients ~= nil and clients[1] ~= nil
end

---@param matches LSPRankedMatch[]
function nil_means_nil(matches)
    -- setting a key to nil in a table effectively removes the key
    -- - FYI vim.NIL means set to null
    --   use vim.NIL if you need to know a key was set to null (python None)
    --
    -- ?? walk the entire response object and delete all the keys with vim.NIL?
    --   IOTW change vim.NIL => nil
    local function nillify(what)
        if what == vim.NIL then
            return nil
        end
        return what
    end
    for _, match in ipairs(matches) do
        -- FYI for now be conservative and only replace vim.NIL on values that you know can be python's None value
        -- and that client side (here in lua) can be nil
        -- 100% when column is not used it should be nil and no other value.. so integer|nil are only values
        match.start_column_base0 = nillify(match.start_column_base0)
        match.end_column_base0 = nillify(match.end_column_base0)
        -- TODO replace other values explicitly here instead of blanket walking entire object...
        --  why? because there is a chance in another context that you might want to differentiate vim.NIL
        --  consider context before blanket replace
    end
    return matches
end

function warn_if_table_has_vim_NIL(what)
    if type(what) ~= "table" then
        return false
    end

    -- FYI yes this is a bit hacky, so what... clean it up when you need it elsewhere
    -- * table
    local found_keys = {}
    for key, value in pairs(what) do
        if value == vim.NIL then
            found_NIL = true
            table.insert(found_keys, key)
        elseif warn_if_table_has_vim_NIL(value) then
            -- FYI defer to root most caller of warn_if_vim_NIL to log entire object
            found_NIL = true
        end
    end
    if #found_keys == 0 then
        return found_NIL
    end

    -- * found keys
    local what_str = vim.inspect(what)
    -- TODO make into general purpose highlighter for logging table + specific keys!
    local lines = vim.split(what_str, "\n", { plain = true })
    for i, line in ipairs(lines) do
        for _, key in ipairs(found_keys) do
            -- make each key stand out
            if line:match("^%s*" .. key .. "%s*=%s*") then
                lines[i] = ansi.bold(ansi.red(line))
                break
            end
        end
    end
    local highlighted_what = table.concat(lines, "\n")

    log:warn("found vim.NIL keys:", found_keys, " on ", highlighted_what)
    return true
end

function walk_for_vim_NIL(what)
    if what == vim.NIL then
        -- TODO get actual code that called this to give as "what was vim.NIL"?
        -- log traceback so you can see "what" as in the expression used to pass `what`
        log:warn("entire object is vim.NIL, here is traceback where this was called:", debug.traceback())
        return
    end
    if not warn_if_table_has_vim_NIL(what) then
        return
    end
    -- PRN if needed log full object (root most) instead of closest table.. so this is the furthest away
    -- log:warn("found vim.NIL on top-level object:", what)
end

--- semantic grep results in an MCP like shape so they readily work with MCP client and models can understand the results
---@class SemanticGrepWithTimeoutResponseObj : MCP_CallToolResponse
---@field result SemanticGrepWithTimeoutResult

---@class SemanticGrepWithTimeoutResult
---@field isError? boolean
---@field error? string
---@field matches? LSPRankedMatch[]

--- Executes a semantic grep request with:
--- - check server is available
--- - supports timeout
---@param semantic_grep_request LSPSemanticGrepRequest
--- @param lsp_buffer_number? integer
---@param callback_like_mcp_tool fun(response_obj: SemanticGrepWithTimeoutResponseObj) -- called with the result or error
---@return integer[] _client_request_ids, fun() _cancel_all_requests
function M.semantic_grep_with_timeout(semantic_grep_request, lsp_buffer_number, callback_like_mcp_tool)
    lsp_buffer_number = lsp_buffer_number or 0
    -- log:info("semantic_grep_request", vim.inspect(semantic_grep_request))
    -- TODO! add logging of semantic_grep request and response (matches) like I do with tracing agents
    -- I want to start cataloging how I feel about various RAG queries and responses
    -- perhaps store here: ~/.local/state/nvim/ask-openai/rag/{rag_type} (or put all RAG into one dir?)
    --   types:
    --   - auto RAG (FIM vs Rewrite vs Agent) - not requested by agent, just bunded as initial context
    --   - semantic_grep agent tool (in-process) - when agent explicitly asks for a RAG search
    --   - semantic_grep telescope plugin
    --   what about diff auto RAG scenarios (FIM vs Rewrite vs Agent)?

    -- normally I'd move closer to first use, but for this LSP cancel scenario, sometimes a nested func wants to use these (with nil check) and I forget about these... so leave here so it is obvious I can use them anywhere if check happens
    local _client_request_ids, _cancel_all_requests, _request_timeout_timer

    ---@param message string
    -- Invokes the provided callback with a standardized error payload.
    -- The function name is chosen to better convey its purpose.
    local function error_response(message)
        callback_like_mcp_tool({
            result = {
                isError = true,
                error = message,
            },
        })
    end

    ---@param lsp_error? lsp.ResponseError
    ---@param lsp_result any
    ---@param context lsp.HandlerContext
    ---@param config? table
    local function on_language_server_response(lsp_error, lsp_result, context, config)
        log:info("OLSR", lsp_error)
        -- FYI connection failure will arive with message:
        -- TODO any special connection failure logic?
        --   "ConnectionRefusedError: [Errno 61] Connect call failed ('IP', PORT)"

        -- walk_for_vim_NIL(lsp_result) -- FYI uncomment for testing known vim.NIL values before replacing with nil_means_nil
        if lsp_result and lsp_result.matches then
            lsp_result.matches = nil_means_nil(lsp_result.matches)
        end
        walk_for_vim_NIL(lsp_result)
        if lsp_error then
            -- IIGC this is a client side error in making the request?
            log:warn("Semantic Grep tool_call query failed (callback err): " .. vim.inspect(lsp_error), lsp_result)
            error_response(lsp_error.message or "unknown error")
            return
        end

        if lsp_result.error ~= nil and lsp_result.error ~= "" then
            -- Language Server errors (returned successfully) hit this pathway

            if lsp_result.error == "Client cancelled query" then
                log:info("client canceled query")
                -- * ok to ignore cancel (b/c client requested it)
                --  otherwise if I don't ignore it here, then I have to ignore it downstream!
                --  why detect this twice?!
                return
            end

            log:luaify_trace("Semantic Grep tool_call lsp_result error, still calling back: ", lsp_result)
            if lsp_result.matches then
                -- not sure this would happen so I am leaving a message to investigate...
                -- I was just blinding forwarding and then I wired up clients to ignore other errors!
                -- yikes so yeah while I am at it, squelch these!
                log:warn("matches present despite error... these will be ignored for now (no use case so far)",
                    vim.inspect(lsp_result.matches))
            end
            error_response(lsp_result.error)
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

        callback_like_mcp_tool({
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

    if not M.is_lsp_client_available(lsp_buffer_number) then
        log:error("ask_language_server is not available")
        vim.schedule(function()
            -- do not synchronously callback on sync failures, most callers check request ids and they won't have those yet.. NBD to cancel in a split second vs instant
            error_response("Semantic Grep aborted... ask_language_server is not available")
        end)
        return {}, function() end
    end

    local function stop_requests()
        if _cancel_all_requests == nil then
            return
        end
        if _request_timeout_timer then
            _request_timeout_timer:stop()
        end
        _cancel_all_requests() -- IIAC same as vim.lsp.cancel_request(0, _client_request_ids) ... so I could skip passing the func around?
        _cancel_all_requests = nil -- avoid double canceling (raises error) i.e. if user cancels after a timeout
    end

    log:info("  BUF_REQUEST")
    _client_request_ids, _cancel_all_requests = vim.lsp.buf_request(lsp_buffer_number, "workspace/executeCommand", params,
        ---@param lsp_error? lsp.ResponseError
        ---@param lsp_result any
        ---@param context lsp.HandlerContext
        ---@param config? table
        function(lsp_error, lsp_result, context, config)
            if _request_timeout_timer then
                _request_timeout_timer:stop()
            end
            on_language_server_response(lsp_error, lsp_result, context, config)
        end)
    log:info("    REQUEST IDs:", _client_request_ids)

    local timeout_ms = 5000
    _request_timeout_timer = vim.defer_fn(function()
        if _cancel_all_requests == nil then -- already canceled
            return
        end
        log:info("Semantic Grep request timed out")
        error_response("Semantic Grep request timed out")
        stop_requests()
    end, timeout_ms)

    return _client_request_ids, stop_requests
end

return M
