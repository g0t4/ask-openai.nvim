local log = require("devtools.logs.logger").universal()
local json = require("dkjson")
local tables = require("ask-openai.helpers.tables")
local ansi = require("devtools.ansi")

local response_metadata = require("ask-openai.backends.response_metadata")
local SSEDeltaWrapped = require("ask-openai.backends.sse_delta_wrapped")

local M = {}

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

-- TODO! 2026-11-27 move to new file when we accumulate in curl backend
---@class AccumulatedCompletion
---@field metadata table
local AccumulatedCompletion = {}

---@return AccumulatedCompletion
function AccumulatedCompletion.new()
    return setmetatable({ metadata = {} }, { __index = AccumulatedCompletion })
end

---@param sse_wrapped SSEWrapped
---@param request CurlRequest|CurlRequestForTrace
---@param frontend StreamingFrontend
function M.log_sse_to_request(sse_wrapped, request, frontend)
    local sse_parsed = sse_wrapped.sse_parsed
    -- TODO! 2026-11-27 didn't last_sse cause some havoc for AgentsFrontend logging the last agent message? is that fixed now that I took out last_sse?

    local function log_raw_completion_sse()
        -- * /v1/completions endpoint
        if sse_parsed.content == nil then
            return
        end

        -- * init accum object and store it on request
        local accumulated_completion = request.accum or AccumulatedCompletion.new()
        request.accum = accumulated_completion

        -- FYI no idea if this would even work beyond llama-server but it would be pluggable for llama-server's timings even if the others never apply in this case
        response_metadata.accumulate_metadata(sse_wrapped, accumulated_completion)

        local function accumulate_content()
            if sse_parsed.content ~= nil then
                accumulated_completion.content = (accumulated_completion.content or "") .. sse_parsed.content
            end
            -- PRN accumulate the finish_reason too?
        end
        accumulate_content()

        -- TODO verify if raw completions even work with new metadata approach (once we're all done with refactors)
        if not accumulated_completion.metadata.done then
            return
        end

        vim.schedule(function()
            M.save_raw_prompt(request, frontend, accumulated_completion)
        end)
    end

    local function log_chat_completion_sse()
        -- * /v1/chat/completions endpoint llama-server
        if sse_parsed.choices == nil then
            return
        end

        -- * init accum object and store it on request
        local accumulated_completion = request.accum or AccumulatedCompletion.new()
        request.accum = accumulated_completion

        response_metadata.accumulate_metadata(sse_wrapped, accumulated_completion)

        local function accumulate_choice(sse)
            if type(sse.choices) ~= "table" or #sse.choices == 0 then
                return
            end

            local choice = sse.choices[1]
            -- PRN warn if > 1 choices? ... we might have done that elsewhere already?
            local delta = choice and choice.delta or {}
            if type(delta) ~= "table" then return end
            -- TODO we should NOT need to check for a delta!!! take this crap out when you redo the accumulator
            -- - requires delta to be empty table else things like finish_reason (not on delta) aren't accumulated!
            -- FYI type(vim.empty_dict()) == "table"
            --  and #(vim.empty_dict()) == 0
            --  and next(vim.empty_dict()) == nil   -- DO NOT USE THIS THOUGH :)
            --  and (vim.empty_dict())[1] == nil -- just like an empty table
            --  and that's good b/c the SSE w/ finish_reason has a choice w/o a delta:
            --    choices = { { delta = vim.empty_dict(), finish_reason = "stop", index = 0 } }

            if delta.role ~= nil then
                accumulated_completion.role = delta.role
            end
            local reasoning_content = SSEDeltaWrapped.new(delta):reasoning()
            if reasoning_content ~= nil then
                accumulated_completion.reasoning_content = (accumulated_completion.reasoning_content or "") .. reasoning_content
            end
            if delta.content ~= nil then
                accumulated_completion.content = (accumulated_completion.content or "") .. delta.content
            end
            if choice and choice.finish_reason ~= nil then
                accumulated_completion.finish_reason = choice.finish_reason
            end
        end

        accumulate_choice(sse_parsed)

        -- PRN drop assistant prefill message before last message in trace?
        --  else these become part of trace too that is sent back to agents!?
        --  right now this happens with prefill to block reasoning with Muse Glimmer
        --  actually I'd need to remove the message over in the AgentsFrontend too (or entirely)
        --  TODO see notes in AgentsFrontend to figure out where I want this
        --   and FYI this can affect any frontend, not just Agents... i.e. PredictionsFrontend using non reasoning FIM with Muse Glimmer

        -- TODO do I add to accumulated_message (via request.accum) in AgentsFrontend for tool calls?
        --   TODO oh wait... when I save this as done does it not have tool call args? until I save a future turn's messages that does have it? cuz I accumulate different message object in frontend?! yikes
        -- PRN track tool call deltas too? on the response (for output.json)?
        --   FYI request.body, on next turn, already has the tool call
        --   so for now, this is not urgent to add to logs here... I can grab trace logs for after model responds to tool call result
        if not accumulated_completion.metadata.done then
            return
        end

        local messages_snapshot = tables.shallow_copy(request.body.messages or {})
        table.insert(messages_snapshot, accumulated_completion)
        vim.schedule(function()
            local vars = { request = request, frontend = frontend, messages_snapshot = messages_snapshot }
            log:info("save_chat_trace log_chat_completion_sse", vars)
            M.save_chat_trace(request, frontend, messages_snapshot)
        end)
    end

    log_raw_completion_sse()
    log_chat_completion_sse()
end

local function path_for(request, frontend)
    local save_dir, trace_id = M.log_request_with(request, frontend)
    -- FYI io write (below) fails if this doesn't exist:
    vim.fn.mkdir(save_dir, "p")
    return save_dir .. "/" .. trace_id .. "-trace.jsonl"
end

--- Encode a trace record to JSON, mapping vim.NIL to null.
---@param record table
local function encode_record(record)
    return json.encode(record, {
        exception = function(reason, bad_value, _, default_message)
            -- FYI vim.NIL shouldn't ever happen, still handle it and log an error
            if reason == "unsupported type" and bad_value == vim.NIL then
                log:error("encountered vim.NIL when it should not be present in completion_logger", reason, bad_value, default_message)
                return "null"
            end

            return nil, default_message
        end,
    })
end

---@param request CurlRequest|CurlRequestForTrace
---@param frontend StreamingFrontend
---@param messages_snapshot? table[]
function M.save_chat_trace(request, frontend, messages_snapshot)
    -- TODO jsonl records:
    -- TODO add turn start/end records
    -- TODO add record w/ type=request_body per turn
    -- TODO add record w/ type=tools at start of trace? and if ever changed

    local path = path_for(request, frontend)
    local messages = messages_snapshot or (request.body and request.body.messages) or {}

    local file = io.open(path, "w")
    if file then
        for _, message in ipairs(messages) do
            -- clone so we can strip metadata from the message itself without
            -- mutating the accumulated_message object still held in-memory
            local message_clone = vim.deepcopy(message)
            local message_metadata = message_clone.metadata
            message_clone.metadata = nil

            local record = {
                type = "message",
                message = message_clone,
                metadata = { response = message_metadata },
            }
            file:write(encode_record(record) .. "\n")
        end
        file:close()
    end
end

--- Save a raw /v1/completions trace (no chat messages).
---@param request CurlRequest|CurlRequestForTrace
---@param frontend StreamingFrontend
---@param accumulated_completion AccumulatedCompletion
function M.save_raw_prompt(request, frontend, accumulated_completion)
    local path = path_for(request, frontend)

    local record = {
        type = "raw_completion",
        -- TODO long prompt as raw_prompt record too (no need to accumulate, just get it off of body)
        -- in fact, why not just treat them as messages?
        content = accumulated_completion.content,
        metadata = { response = accumulated_completion.metadata },
    }

    local vars = { request = request, frontend = frontend, record }
    log:info("save_raw_prompt log_raw_completion_sse", vars)

    local file = io.open(path, "w")
    if file then
        file:write(encode_record(record) .. "\n")
        file:close()
    end
end

return M
