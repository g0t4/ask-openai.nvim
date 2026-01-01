local log = require('ask-openai.logs.logger').predictions()

local M = {
    last_done = {},
    LOG_ALL_SSEs = true,
    -- LOG_ALL_SSEs = false,
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

    if sse_parsed.timings then
        -- store for convenient access in-memory, that way if smth fails on save I can still see it here
        M.last_done = {
            sse_parsed = sse_parsed,
            request = request,
            frontend = frontend,
        }

        local request_dir = vim.fn.stdpath("state") .. "/ask-openai" .. "/" .. tostring(sse_parsed.created)
        log:error("request_dir", request_dir)

        vim.defer_fn(function()
            vim.fn.mkdir(request_dir, "p")

            local request_file = io.open(request_dir .. "/output.json", "w")
            if request_file then
                request_file:write(vim.json.encode(request.accum))
                request_file:close()
            end

            local input_messages_file = io.open(request_dir .. "/input-body.json", "w")
            if input_messages_file then
                input_messages_file:write(vim.json.encode(request.body))
                input_messages_file:close()
            end

            if sse_parsed.__verbose then
                -- PRN do I really want this separate, too?
                local input_prompt_file = io.open(request_dir .. "/input-prompt.txt", "w")
                if input_prompt_file then
                    input_prompt_file:write(sse_parsed.__verbose.prompt)
                    input_prompt_file:close()
                end
            end

            -- .timings (top-level and under .__verbose.timings)
            -- .__verbose.(prompt, generation_settings)
            -- .__verbose.content (generated raw outputs, but ONLY for stream=false)
            local request_file = io.open(request_dir .. "/last_sse.json", "w")
            if request_file then
                request_file:write(vim.json.encode(sse_parsed))
                request_file:close()
            end

            if M.LOG_ALL_SSEs then
                local all_file = io.open(request_dir .. "/all_sses.json", "w")
                if all_file then
                    all_file:write(vim.json.encode(all_sses))
                    all_file:close()
                end
            end
        end, 0)
    end
end

return M
