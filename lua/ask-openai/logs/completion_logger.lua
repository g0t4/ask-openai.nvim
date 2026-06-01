local log = require("ask-openai.logs.logger").predictions()
local json = require("dkjson")

local M = {
    last_done = {},
}
---@param request CurlRequest|CurlRequestForTrace
---@param frontend StreamingFrontend
---@return string save_dir
---@return string trace_id
function M.log_request_with(request, frontend)
    local save_dir = vim.fn.stdpath("state") .. "/ask-openai"
    if request.type ~= "" then
        -- add `agents/` or `fim/` or `rewrite/` intermediate path
        save_dir = save_dir .. "/" .. request.type
    end
    local trace_id = tostring(request.start_time)
    if frontend.trace then
        -- multi-turn traces use trace's start_time
        trace_id = tostring(frontend.trace.start_time)
    end
    return save_dir, trace_id
end

---@param sse_parsed table
---@param request CurlRequest|CurlRequestForTrace
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

    local accum = request.accum or {}
    request.accum = accum

    local choices = sse_parsed.choices
    if not choices then
        return
    end
    local first = choices[1]
    if not first then
        return
    end
    local delta = first.delta
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
    --   so for now, this is not urgent to add to logs here... I can grab trace logs for after model responds to tool call result

    local is_last_sse = sse_parsed.timings
    if is_last_sse then
        -- store for convenient access in-memory, that way if smth fails on save I can still see it here
        M.last_done = {
            sse_parsed = sse_parsed,
            request = request,
            frontend = frontend,
        }

        local save_dir, trace_id = M.log_request_with(request, frontend)

        vim.schedule(function()
            -- technically I have timing issues here, this could run after below (IIUC)
            --  if so, then IIAC I can schedule the file writing for all of the below too and they'd be behind this then, right?
            vim.fn.mkdir(save_dir, "p")
        end)

        -- TODO merge into logic in AgentsFrontend so I can just capture response_message as part of request_body.messages and not log that separately anymore
        -- TODO what (if anything) is missing for the trace_message that AgentsFrontend inserts into trace history vs the accum here
        --  OR, was it just that I was duplicating the assistant message (randomly b/c that logic to insert the new message would execute before/after this saved b/c this used to be async via vim.vim.defer_fn(function() ... end,0)
        --    btw if it was just duplicates, then now that I do not vim.defer_fn anymore for this part then timing wise the trace_message can't be added
        M.save_trace(request, frontend, accum, sse_parsed)
    end
end

---@param request CurlRequest|CurlRequestForTrace
---@param frontend StreamingFrontend
---@param response_message table
---@param sse_parsed table
function M.save_trace(request, frontend, response_message, sse_parsed)
    local save_dir, trace_id = M.log_request_with(request, frontend)
    local path = save_dir .. "/" .. trace_id .. "-trace.json"
    -- log:info("trace path", path)
    local file = io.open(path, "w")
    if file then
        -- TODO move this logic for AgentsFrontend too? if I keep trace (I plan to ditch it)
        local trace_data = {
            -- 99.99% of the time this is all I need (input messages trace + output message):
            request_body = request.body,
            response_message = response_message,
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
        file:write(json.encode(trace_data, { indent = true }))
        file:close()
    end
end

return M
