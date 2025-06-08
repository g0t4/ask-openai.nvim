local M = {}
local log = require("ask-openai.prediction.logger").predictions()

local function body_for(prefix, suffix)
    local body = {

        model = "fim_qwen:7b-instruct-q8_0",

        -- /v1/completions DOES NOT USE A TEMPLATE AFAICT in llama-server
        prompt = prefix,
        suffix = suffix,

        stream = true,
        max_tokens = 200,
    }

    return vim.json.encode(body)
end

function M.build_request(prefix, suffix)
    local options = {
        command = "curl",
        args = {
            "--fail-with-body",
            "-sSL",
            "--no-buffer",
            "-X", "POST",
            "http://ollama:8012/v1/completions",
            "-H", "Content-Type: application/json",
            "-d", body_for(prefix, suffix)
        },
    }
    return options
end

function M.process_sse(data)
    -- SSE = Server-Sent Event
    -- split on lines first (each SSE can have 0+ "event" - one per line)

    -- FYI use nil to indicate nothing in the SSE... vs empty line which is a valid thingy right?
    local chunk = nil -- combine all chunks into one string and check for done
    local done = false
    local finish_reason = nil
    for ss_event in data:gmatch("[^\r\n]+") do
        if ss_event:match("^data:%s*%[DONE%]$") then
            -- done, courtesy last event... mostly ignore b/c finish_reason already comes on the prior SSE
            return chunk, true
        end

        --  strip leading "data: " (if present)
        local event_json = ss_event
        if ss_event:sub(1, 6) == "data: " then
            -- ollama /api/generate doesn't prefix each SSE with 'data: '
            -- IIRC /v1/completions doesn't do this
            event_json = ss_event:sub(7)
        end
        local success, parsed = pcall(vim.json.decode, event_json)

        if success and parsed.choices and parsed.choices[1] and parsed.choices[1].text then
            local choice = parsed.choices[1]
            local text = choice.text
            finish_reason = choice.finish_reason
            if choice.finish_reason == "stop" then
                done = true
            elseif choice.finish_reason == "length" then
                done = true
            elseif choice.finish_reason ~= vim.NIL then
                log:warn("WARN - unexpected /v1/completions finish_reason: ", choice.finish_reason, " do you need to handle this too?")
                -- ok for now to continue too
                done = true
            end
            chunk = (chunk or "") .. text
        else
            log:warn("SSE json parse failed for ss_event: ", ss_event)
        end
    end
    -- TODO test passing back finish_reason (i.e. for an empty prediction log entry)
    return chunk, done, finish_reason
end

return M
