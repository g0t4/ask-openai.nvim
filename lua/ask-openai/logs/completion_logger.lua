local log = require('ask-openai.logs.logger').predictions()
local json = require('dkjson')

local M = {
    last_done = {},
    -- LOG_ALL_SSEs = true,
    LOG_ALL_SSEs = false,
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

    if M.LOG_ALL_SSEs then
        all_sses = request.all_sses or {}
        request.all_sses = all_sses

        all_sses[#all_sses + 1] = sse_parsed
    end

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
        accum.finish_reason = first.finish_reason
    end
    -- PRN track tool call deltas too? on the response (for output.json)?
    --   FYI request.body, on next turn, already has the tool call
    --   so for now, this is not urgent to add to logs here... I can grab thread logs for after model responds to tool call result

    if sse_parsed.timings then
        -- store for convenient access in-memory, that way if smth fails on save I can still see it here
        M.last_done = {
            sse_parsed = sse_parsed,
            request = request,
            frontend = frontend,
        }

        ---@param request CurlRequest
        ---@param frontend StreamingFrontend
        ---@return string save_dir, string thread_id
        function where_to_save(request, frontend)
            local save_dir = vim.fn.stdpath("state") .. "/ask-openai"
            if request.type ~= "" then
                -- add `questions/` or `fim/` or `rewrite/` intermediate path
                save_dir = save_dir .. "/" .. request.type
            end
            local thread_id = tostring(request.start_time)
            if frontend.thread then
                -- multi-turn threads use thread's start_time
                thread_id = tostring(frontend.thread.start_time)
            end
            return save_dir, thread_id
        end

        local save_dir, thread_id = where_to_save(request, frontend)

        if M.LOG_ALL_SSEs then
            -- PRN save to 123-sses.jsonl
            --   SSEs are fairly standardized => thus jsonl would likely read table-like
            --   for all but first(s)/last(s)
            --
            -- create dir for multiple files (one per SSE)
            save_dir = save_dir .. "/" .. thread_id
        end

        vim.defer_fn(function()
            vim.fn.mkdir(save_dir, "p")
            -- TODO append new message to -messages.jsonl (new line, compact)

            local path = save_dir .. "/" .. thread_id .. "-thread.json"
            -- log:info("thread path", path)
            local file = io.open(path, "w")
            if file then
                local thread_data = {
                    -- 99.99% of the time this is all I need (input messages thread + output message):
                    request_body = request.body,
                    response_message = request.accum,
                    --
                    -- FYI must use llama-server's --verbose flag .__verbose.* on last_sse
                    --   __verbose.prompt basically repeats request.body, thus not needed
                    --   rendered prompt can be nice for reproducibility
                    --     but, you can also use /apply-template endpoint to generate it too
                    --     obviously won't capture template changes when rendering
                    --
                    -- last_sse has:
                    --   .timings (top-level and under .__verbose.timings)
                    --   .__verbose.(prompt, generation_settings)
                    --   .__verbose.content (generated raw outputs, but ONLY for stream=false)
                    last_sse = sse_parsed,
                }
                file:write(json.encode(thread_data, { indent = true }))
                file:close()
            end

            if M.LOG_ALL_SSEs then
                local all_file = io.open(save_dir .. "/all_sses.json", "w")
                if all_file then
                    all_file:write(json.encode(all_sses, { indent = true }))
                    all_file:close()
                end
            end
        end, 0)
    end
end

return M
