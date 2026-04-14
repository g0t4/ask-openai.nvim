local log = require('ask-openai.logs.logger').predictions()
local json = require('dkjson')

local M = {
    last_done = {},
    -- LOG_ALL_SSEs = true,
    LOG_ALL_SSEs = false,
}
---@param request CurlRequest
---@param frontend StreamingFrontend
---@return string save_dir
---@return string trace_id
function M.log_request_with(request, frontend)
    local save_dir = vim.fn.stdpath("state") .. "/ask-openai"
    if request.type ~= "" then
        -- add `questions/` or `fim/` or `rewrite/` intermediate path
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
    --   so for now, this is not urgent to add to logs here... I can grab trace logs for after model responds to tool call result

    if sse_parsed.timings then
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

        if request.type ~= "agents" then
            -- PredictionsFrontend and RewriteFrontend are both single turn, and can log assistant response message(s) here
            M.append_to_messages_jsonl(accum, request, frontend)
        end
        -- TODO check timing of AgentsFrontend now and ALSO check what (if anything) is missing here for the trace_message that AgentsFrontend inserts into trace history vs the accum here
        --  does accum have all of what's needed or is it missing anything (IIRC I vaguely recall there's something I distilled special in AgentsFrontend that wouldn't be on the pure accum message here)
        --  OR, was it just that I was duplicating the assistant message (randomly b/c that logic to insert the new message would execute before/after this saved b/c this used to be async via vim.vim.defer_fn(function() ... end,0)
        --    btw if it was just duplicates, then now that I do not vim.defer_fn anymore for this part then timing wise the trace_message can't be added
        M.save_trace(request, frontend, accum, sse_parsed)
        -- TODO consider if you want part of what trace has (i.e. other request body inputs)... perhaps just log that separately? in another file? and then not log *-trace.json anymore and just rely on messages.jsonl?
        --  that said I was unhappy with messages alone today too so gahhh (I also ripped out messages.jsonl)

        if M.LOG_ALL_SSEs then
            -- PRN save to 123-sses.jsonl?
            --   SSEs are fairly standardized => thus jsonl would likely read table-like
            --   for all but first(s)/last(s)
            local all_file = io.open(save_dir .. "/" .. trace_id .. "/all_sses.json", "w")
            if all_file then
                all_file:write(json.encode(all_sses, { indent = true }))
                all_file:close()
            end
        end
    end
end

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

---@param request CurlRequest
---@param frontend StreamingFrontend
function M.write_new_messages_jsonl(request, frontend)
    -- Save the initial request payload (messages) before sending, for any frontend that uses Curl.
    local body = request.body
    local messages = body and body.messages -- messages is nil if body is nil, else has body.messages
    if not messages then
        log:info("no messages found (request.body.messages)... happens for qwen FIM b/c it uses raw prompt (TODO capture the raw prompt instead)?")
        return
    end
    local ok, payload = pcall(function()
        -- * each message on its own (initial request has multiple messages)
        --  PRN do I really like this style? how about just pretty print with back to back messages :) and not deal with "jsonl"
        --  TODO only append new message - long assistant traces will increase each turn, the time it takes and since I recreate each time... it's going to be painful (possibly... as in 10ms? each turn... which is FINE for now :) )
        --   TODO how about flag each message as logged? (after logged so not logging that)
        --    currently re-saving entire trace every time
        local message_lines = {}
        for _, msg in ipairs(messages) do
            if not msg._logged then
                local json_string = json.encode(msg,
                    { indent = false } -- compact/oneline
                )
                table.insert(message_lines, json_string)
                -- log:info("logging message", json_string)
                msg._logged = true
            end
        end
        return table.concat(message_lines, "\n")
    end)
    if ok then
        local save_dir, trace_id = M.log_request_with(request, frontend)

        vim.fn.mkdir(save_dir, "p")
        local path = save_dir .. "/" .. trace_id .. "-messages.jsonl"
        local file = io.open(path, "a")
        if file then
            file:write("\n") -- instead of trailing \n, prepend a \n to ensure never colliding with current message on last line
            file:write(payload)
            file:close()
            log:info("Saved initial curl request to", path)
        else
            log:error("Unable to write initial curl request to", path)
        end
    else
        log:error("Failed to encode initial curl request", payload)
    end
end

---@param request CurlRequest
---@param frontend StreamingFrontend
function M.append_to_messages_jsonl(message, request, frontend)
    -- FYI 0.1 ms for this func to run (a few tests) - NBD to be saving redundant info that's also in *-trace.json

    -- FYI I am keeping *-trace.json for now until I have time to update my chat viewer for -messages.jsonl
    --   I don't think I need anything beyond messages from -trace.json... if not then I'll ditch -trace.json most likely
    --   if I do need more, it will be a while (if ever) before I fully stop using -trace.json

    local oneline = { indent = false }
    local json_line = vim.json.encode(message, oneline)

    local save_dir, trace_id = M.log_request_with(request, frontend)
    local path = save_dir .. "/" .. trace_id .. "-messages.jsonl"
    local file, err = io.open(path, "a")
    if not file then
        log:error("Failed to open messages log for appending: %s", err)
    else
        message._logged = true
        file:write("\n") -- instead of trailing \n, prepend a \n to ensure never colliding with current message on last line
        file:write(json_line)
        file:close()
    end
end

return M
