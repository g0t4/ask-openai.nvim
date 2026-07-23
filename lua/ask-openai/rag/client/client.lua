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

--- Executes a semantic grep request with:
--- - check server is available
--- - supports timeout
---@param semantic_grep_request LSPSemanticGrepRequest
--- @param lsp_buffer_number? integer
---@param callback fun(result: table) -- called with the result or error
---@return table _client_request_ids, fun() _cancel_all_requests
function M.semantic_grep_with_timeout(semantic_grep_request, lsp_buffer_number, callback)
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
        -- walk_for_vim_NIL(lsp_result) -- FYI uncomment for testing known vim.NIL values before replacing with nil_means_nil
        if lsp_result and lsp_result.matches then
            lsp_result.matches = nil_means_nil(lsp_result.matches)
        end
        walk_for_vim_NIL(lsp_result)
        if err then
            -- IIGC this is a client side error in making the request?
            log:luaify_trace("Semantic Grep tool_call query failed (callback err): " .. vim.inspect(err), lsp_result)
            error_response(err.message or "unknown error")
            return
        end

        if lsp_result.error ~= nil and lsp_result.error ~= "" then
            -- Language Server errors (returned successfully) hit this pathway

            if lsp_result.error == "Client cancelled query" then
                -- no caller would need to get a callback
                return
            end

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

    if not M.is_lsp_client_available(lsp_buffer_number) then
        log:error("ask_language_server is not available")
        error_response("Semantic Grep aborted... ask_language_server is not available")
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

    _client_request_ids, _cancel_all_requests = vim.lsp.buf_request(lsp_buffer_number, "workspace/executeCommand", params, function(err, result, ctx, config)
        if _request_timeout_timer then
            _request_timeout_timer:stop()
        end
        on_language_server_response(err, result, ctx, config)
    end)

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
