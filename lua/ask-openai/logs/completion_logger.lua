local log = require("devtools.logs.logger").universal()
local json = require("dkjson")
local tables = require("ask-openai.helpers.tables")
local ansi = require("devtools.ansi")

local response_metadata = require("ask-openai.backends.response_metadata")
local response_reasoning = require("ask-openai.backends.response_reasoning")

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
    -- TODO! didn't last_sse cause some havoc for AgentsFrontend logging the last agent message? is that fixed now that I took out last_sse?

    local function is_raw_completion_endpoint(sse)
        return sse.content ~= nil
    end

    local function log_raw_completion_sse()
        -- * /v1/completions endpoint
        if not is_raw_completion_endpoint(sse_parsed) then
            return
        end

        local accumulated_message = request.accum or {
            request_metadata = {}
        }
        request.accum = accumulated_message

        -- * accumulate content
        if sse_parsed.content ~= nil and sse_parsed.content ~= vim.NIL then
            accumulated_message.content = (accumulated_message.content or "") .. sse_parsed.content
        end
        -- PRN accumulate the finish_reason too?

        if not accumulated_message.request_metadata.done then
            return
        end

        M.last_done = {
            request  = request,
            frontend = frontend,
        }
        local trace_data = {
            -- put content on trace_data top-level
            content = accumulated_message.content,
        }
        vim.schedule(function()
            local no_messages = nil -- b/c not chat endpoint
            local vars = { request = request, frontend = frontend, messages_snapshot = no_messages, trace_data = trace_data }
            log:info("save_trace log_raw_completion_sse", vars)
            M.save_trace(request, frontend, no_messages, trace_data)
        end)
    end

    local function is_chat_completion_endpoint(sse)
        return sse.choices ~= nil
    end

    local function log_chat_completion_sse()
        -- * /v1/chat/completions endpoint llama-server
        if not is_chat_completion_endpoint(sse_parsed) then
            return
        end

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
        -- * init accum object and store it on request
        local accumulated_message = request.accum or {
            request_metadata = {}
        }
        request.accum = accumulated_message

        response_metadata.accumulate(sse_parsed, accumulated_message)

        local function accumulate_choice(sse)
            if type(sse.choices) ~= "table" or #sse.choices == 0 then
                return
            end

            local choice = sse.choices[1]
            -- PRN warn if > 1 choices? ... we might have done that elsewhere already?
            local delta = choice and choice.delta or {}
            if type(delta) ~= "table" then return end

            if delta.role and delta.role ~= vim.NIL then
                accumulated_message.role = delta.role
            end
            local reasoning_content = response_reasoning.get_content(delta)
            if reasoning_content ~= nil then
                accumulated_message.reasoning_content = (accumulated_message.reasoning_content or "") .. reasoning_content
            end
            if delta.content and delta.content ~= vim.NIL then
                accumulated_message.content = (accumulated_message.content or "") .. delta.content
            end
            if choice and choice.finish_reason and choice.finish_reason ~= vim.NIL then
                accumulated_message.finish_reason = choice.finish_reason
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
        if not accumulated_message.request_metadata.done then
            return
        end

        -- store for convenient access in-memory, that way if smth fails on save I can still see it here
        M.last_done = {
            request = request,
            frontend = frontend,
        }

        -- TODO jsonl_record logs (take .request_body.messages => message records,  rest of .request_body => type=request ? to capture inputs, and type=tools? for tool definitions specifically?)

        -- FYI going forward we will capture entire SSE as metadata (so we'd have raw prompt from llama-server there if we enable verbose mode)
        --  and we'd have it for every turn!

        local messages_snapshot = tables.shallow_copy(request.body.messages or {})
        table.insert(messages_snapshot, accumulated_message)
        vim.schedule(function()
            local vars = { request = request, frontend = frontend, messages_snapshot = messages_snapshot }
            log:info("save_trace log_raw_completion_sse", vars)
            local trace_data = {}
            M.save_trace(request, frontend, messages_snapshot, trace_data)
        end)
    end

    log_raw_completion_sse()
    log_chat_completion_sse()
end

---@param request CurlRequest|CurlRequestForTrace
---@param frontend StreamingFrontend
---@param messages_snapshot? table[]
function M.save_trace(request, frontend, messages_snapshot, trace_data)
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

        if frontend.get_flags_wrapper then
            -- flag traces for later review, especially traces with a knonw issue that you're working on
            -- TODO add a thumbs up keymap for all trace types?
            --  ? OR,  update file on accept using jq command to insert thumbs up or w/e details? (rewrites and predictions would use that)
            local flags = frontend.get_flags_wrapper()
            if flags then
                trace_data.flags = flags
            end
        end

        local encoded = json.encode(trace_data, {
            indent = true,
            exception = function(reason, bad_value, _, default_message)
                if reason == "unsupported type" and bad_value == vim.NIL then
                    return "null"
                end

                return nil, default_message
            end,
        })
        file:write(encoded)
        file:close()
    end
end

return M
