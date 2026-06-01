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

--- shallow copy only copies the top-level table "container"
--- keys are copied w/ respective values, but values are not copied (use vim.deep_copy for that)
--- works with both list tables and maps
local function shallow_copy_table(tbl)
    if not tbl then
        return {}
    end
    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = v
    end
    setmetatable(copy, getmetatable(tbl))
    return copy
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

        local messages_snapshot = shallow_copy_table(request.body.messages or {})
        table.insert(messages_snapshot, accum)
        vim.schedule(function()
            M.save_trace(request, frontend, messages_snapshot, sse_parsed)
        end)
    end
end

---@param request CurlRequest|CurlRequestForTrace
---@param frontend StreamingFrontend
---@param messages_snapshot table[]
---@param sse_parsed table
function M.save_trace(request, frontend, messages_snapshot, sse_parsed)
    local save_dir, trace_id = M.log_request_with(request, frontend)
    -- FYI if this doesn't exist before the save_trace io write happens, the io write will fail silently
    vim.fn.mkdir(save_dir, "p")

    local path = save_dir .. "/" .. trace_id .. "-trace.json"
    -- log:info("trace path", path)
    local file = io.open(path, "w")
    if file then
        local request_body_copy = shallow_copy_table(request.body)
        -- this way I can avoid issues with timing and AgentsFrontend modifying request.body.messages to add its distilled version of the assistant message
        request_body_copy.messages = messages_snapshot
        local trace_data = {
            request_body = request_body_copy,
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
