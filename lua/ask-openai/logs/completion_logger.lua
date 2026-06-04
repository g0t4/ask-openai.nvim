local log = require("ask-openai.logs.logger").predictions()
local json = require("dkjson")
local tables = require("ask-openai.helpers.tables")

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
    local is_last_sse = sse_parsed.timings -- timings only on last sse

    function M.log_raw_completion_sse()
        -- * /v1/completions endpoint
        -- raw as in there is no chat template that is used to transform messages => raw prompt
        -- instead you provide the raw prompt in the request
        --
        -- NOTE: llama.cpp /completions endpoint works with raw prompt and response (content)
        -- llama.cpp /completions SSEs are split: early SSEs have { content: "...", stop: false }
        -- and the final SSE has { stop: true, timing: true, timings: {...} } WITHOUT content.
        -- So we accumulate content across events, just like the chat endpoint does for delta.content.
        --
        -- TODO modify chat viewers to support this format (.content .request_body.prompt) => can even support raw prompt on regular chat completions too if .__verbose.prompt is present
        --  if no messages => if prompt => show raw prompt, if content => show raw content
        --    add model specific syntax prompt highligthing ... at least color key tags like <im_start> in basic chat formats
        --    could lookup on model id/name
        --
        --  TODO look into llama-server option to return .__verbose.content with raw completion even on chat completions and even on streaming responses!
        --     OR tag it onto my verbose flag that I already read off of request body!
        local accum = request.accum or {}
        request.accum = accum

        if sse_parsed.content ~= nil and sse_parsed.content ~= vim.NIL then
            accum.content = (accum.content or "") .. sse_parsed.content
        end

        if is_last_sse then
            M.last_done = {
                sse_parsed = sse_parsed,
                request    = request,
                frontend   = frontend,
            }
            local trace_data = {
                -- put content on trace_data top-level
                content = accum.content,
            }
            vim.schedule(function()
                local no_messages = nil -- b/c not chat endpoint
                M.save_trace(request, frontend, no_messages, sse_parsed, trace_data)
            end)
        end
    end

    log:info("sse_parsed", vim.inspect(sse_parsed))

    -- Replace the original block with a call to the new helper:
    local is_raw_completion = sse_parsed.content ~= nil -- instead of sse_parsed.choices
    if is_raw_completion then
        M.log_raw_completion_sse()
        return
    end

    -- * /v1/chat/completions endpoint llama-server
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
    -- accum the full message (from streaming SSEs) so I can log for all frontends here
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
    if is_last_sse then
        -- store for convenient access in-memory, that way if smth fails on save I can still see it here
        M.last_done = {
            sse_parsed = sse_parsed,
            request = request,
            frontend = frontend,
        }

        local messages_snapshot = tables.shallow_copy(request.body.messages or {})
        -- FYI it is possible the distill in AgentsFrontend has a difference that you need to keep, if so then call save_trace from that spot and not here just for AgentsFrontend (find a way to pass last_sse, that's the only complexity)
        table.insert(messages_snapshot, accum)
        vim.schedule(function()
            M.save_trace(request, frontend, messages_snapshot, sse_parsed, {})
        end)
    end
end

---@param request CurlRequest|CurlRequestForTrace
---@param frontend StreamingFrontend
---@param messages_snapshot? table[]
---@param last_sse table
function M.save_trace(request, frontend, messages_snapshot, last_sse, trace_data)
    local save_dir, trace_id = M.log_request_with(request, frontend)
    -- FYI if this doesn't exist before the save_trace io write happens, the io write will fail silently
    vim.fn.mkdir(save_dir, "p")

    local path = save_dir .. "/" .. trace_id .. "-trace.json"
    -- log:info("trace path", path)
    local file = io.open(path, "w")
    if file then
        local request_body_copy = tables.shallow_copy(request.body)
        -- this way I can avoid issues with timing and AgentsFrontend modifying request.body.messages to add its distilled version of the assistant message
        -- TODO FYI it is confusing that you add the new message to the messages collection that is marked as request_body.messages... maybe you should just store them separately? and nuke request_body.messages to avoid duplication? like top-level messages?
        if messages_snapshot ~= nil then
            -- PRN move this out to caller of save_trace? use trace_data object?
            request_body_copy.messages = messages_snapshot
        end
        trace_data = trace_data or {}
        trace_data.request_body = request_body_copy
        -- last_sse has:
        --   .timings (top-level and under .__verbose.timings)
        --   .__verbose.(prompt, generation_settings)
        --   .__verbose.content (generated raw outputs, but ONLY for stream=false)
        trace_data.last_sse = last_sse

        file:write(json.encode(trace_data, { indent = true }))
        file:close()
    end
end

return M
