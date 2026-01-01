local log = require('ask-openai.logs.logger').predictions()

local M = {
    last = {}
}


---@param sse_parsed table
---@param request CurlRequest
---@param frontend StreamingFrontend
function M.log_sse_to_request(sse_parsed, request, frontend)
    -- FYI delta is the part that changes per SSE, except for last SSE which sets other fields like finish_reason
    -- * key parts (in order):
    --
    -- first delta has role (not split apart on multiple SSEs)
    -- delta = { content = vim.NIL, role = "assistant" },
    --
    -- reasoning_content SSEs
    -- delta = { reasoning_content = "User" },
    --
    -- content SSEs
    -- delta = { content = "---@" },
    --
    -- last SSE choices:
    -- choices = { { delta = vim.empty_dict(), finish_reason = "stop", index = 0 } },

    accum = request.accum or {}
    request.accum = accum


    choices = sse_parsed.choices
    if not choices then
        return
    end
    first = choices[1]
    if not first then
        return
    end
    delta = first.delta
    if not delta then
        return
    end

    if delta.role then
        accum.role = delta.role
    end
    if delta.reasoning_content and delta.reasoning_content ~= vim.NIL then
        accum.reasoning_content = (accum.reasoning_content or "") .. delta.reasoning_content
    end
    if delta.content and delta.content ~= vim.NIL then
        accum.content = (accum.content or "") .. delta.content
    end
    if first.finish_reason and first.finish_reason ~= vim.NIL then
        -- FYI will be on last SSE
        -- ok to store this on accum too
        accum.finish_reason = first.finish_reason
    end

    if sse_parsed.timings then
        -- TODO log_sse_non_blocking => auto-save to disk (as long as it is not blocking)
        M.auto_save_to_disk(sse_parsed, request, frontend)
    end
end

-- TODO can I use this approach for building the diff too? and if new tokens arrive then discard the diff, and increase the throttle?
--   would it meaningfully help perf?
--   TODO only add this if I can measure perf benefit
--
-- function M.log_sse_non_blocking(???)
--     -- Run the potentially blocking logger in a libuv thread pool.
--     vim.loop.new_thread(function()
--         -- This runs in a worker thread; keep it pure Lua.
--         -- TODO expensive, i.e. file write
--     end, function(_, result)
--         -- This callback runs back on the main thread.
--         -- If the logger returns data that needs to be processed,
--         -- do it here (e.g., update UI buffers, flash messages, etc.).
--         if result then
--             -- Example: refresh a buffer displaying the completion.
--             vim.schedule(function()
--                 -- Assuming `frontend:update` refreshes the UI.
--                 if frontend.update then
--                     frontend:update(result)
--                 end
--             end)
--         end
--     end)
-- end

---@param sse_parsed table
---@param request CurlRequest
---@param frontend StreamingFrontend
function M.auto_save_to_disk(sse_parsed, request, frontend)
    -- store for convenient access in-memory, that way if smth fails on save I can still see it here
    M.last = {
        sse_parsed = sse_parsed,
        request = request,
        frontend = frontend,
    }

    local nvim_state_dir = vim.fn.stdpath("state")
    local ask_dir = nvim_state_dir .. "/ask-openai"
    local request_dir = ask_dir .. "/" .. tostring(sse_parsed.created)

    vim.fn.mkdir(request_dir, "p")

    local request_json_path = request_dir .. "/request.json"
    local input_messages_path = request_dir .. "/input-messages.json"
    local input_prompt_path = request_dir .. "/input-prompt.json"

    local request_file = io.open(request_json_path, "w")
    if request_file then
        request_file:write(vim.inspect(request))
        request_file:close()
    end

    local input_messages_file = io.open(input_messages_path, "w")
    if input_messages_file then
        input_messages_file:write(vim.inspect(request.body))
        input_messages_file:close()
    end

    local input_prompt_file = io.open(input_prompt_path, "w")
    if input_prompt_file then
        input_prompt_file:write(vim.inspect(sse_parsed.__verbose.prompt))
        input_prompt_file:close()
    end

    log:error("created", sse_parsed.created)
    log:error("final SSE", vim.inspect(sse_parsed))
    log:error("request.json", vim.inspect(request))
    log:error("input-messages.json", vim.inspect(request.body))
    log:error("input-prompt.json", vim.inspect(sse_parsed.__verbose.prompt))

    -- FYI if stream=false, then the last SSE has .__verbose.content (but not for streaming)
end

return M
