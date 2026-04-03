local ansi = require("ask-openai.predictions.ansi")
local log = require("ask-openai.logs.logger").predictions()

local M = {}

--- Checks if a given LSP client is attached to the current buffer.
--- @param lsp_buffer_number? integer
--- @return boolean
function M.is_lsp_client_available(lsp_buffer_number)
    lsp_buffer_number = lsp_buffer_number or 0
    local clients = vim.lsp.get_clients({ name = "ask_language_server", bufnr = lsp_buffer_number })
    return clients ~= nil and clients[1] ~= nil
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
