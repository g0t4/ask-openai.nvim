local uv = vim.uv
local M = {}
local Prediction = require("ask-openai.prediction.prediction")

-- FYI would need current prediction PER buffer in the future if want multiple buffers to have predictions at same time (not sure I want this feature)
M.current_prediction = nil -- set on module for now, just so I can inspect it easily

-- FYI useful to observe what is happening under hood, run in pane below nvim (don't need to esc and look at :messages)
--    tail -f /Users/wesdemos/.local/share/nvim/ask/ask-predictions.log
M.logger = require("ask-openai.prediction.logger"):new("ask-predictions.log")
local function info(...)
    M.logger:log(...)
end
if not require("ask-openai.config").get_options().verbose then
    info = function(...)
        -- no-op
    end
end

-- info("foo", nil, "bar") -- use to validate nil args don't interupt the rest of log args getting included -- nuke this is fine, just leaving as a reminder I had trouble with logging nil values
function M.ask_for_prediction()
    info("Asking for prediction...")
    M.stop_current_prediction()

    local Job = require("plenary.job")

    local options = {
        command = "curl",
        args = {
            "-fsSL",
            "-X", "POST",
            "http://build21.lan:11434/v1/chat/completions",
            "-H", "Content-Type: application/json",
            "-d", '{"model": "qwen2.5-coder:3b", "messages": [{"role": "user", "content": "Hello, how are you?"}], "stream": true}'
        }
    }
    -- closure captures this id for any callbacks to use to ignore past predictions
    local this_prediction = Prediction:new()
    M.current_prediction = this_prediction

    options.on_exit = function(job, code, signal)
        info("on_exit code:", vim.inspect(code), "Signal:", signal)
        if code ~= 0 then
            this_prediction:generation_failed()
        else
            this_prediction:generation_finished()
        end
    end

    local function process_sse(data)
        -- TODO add some tests of this parsing? can run outside of nvim too
        -- SSE = Server-Sent Event
        -- split on lines first (each SSE can have 0+ "event" - one per line)
        for line in data:gmatch("[^\r\n]+") do
            if line:match("^data:%s*%[DONE%]$") then
                -- done, courtesy last event... mostly ignore b/c finish_reason already comes on the prior SSE
                return ""
            end

            --  strip leading "data: "
            if line:sub(1, 6) == "data: " then
                local json_str = line:sub(7)
                local success, parsed = pcall(vim.json.decode, json_str)
                if success and parsed.choices and parsed.choices[1] and parsed.choices[1].delta and parsed.choices[1].delta.content then
                    local choice = parsed.choices[1]
                    local content = choice.delta.content
                    if choice.finish_reason == "stop" then
                        -- support other finish_reasons?
                        return content, true
                    elseif choice.finish_reason ~= vim.NIL then
                        info("WARN - unexpected finish_reason: ", choice.finish_reason, " do you need to handle this too?")
                    end
                    return content, false
                else
                    info("SSE json parse failed for: ", json_str)
                end
            else
                info("Ignoring SSE event: ", line)
            end
        end
        return nil
    end

    options.on_stdout = function(err, data, job)
        info("on_stdout data: ", data, "err: ", err)
        -- FYI, with plenary.job, on_stdout/on_stderr are both called one last time (with nil data) after :shutdown is called... NBD just a reminder
        if err then
            this_prediction:generation_failed()
            return
        end

        if data then
            vim.schedule(function()
                local chunk = process_sse(data)
                if chunk and chunk ~= "" then
                    this_prediction:add_chunk_to_prediction(chunk)
                end
            end)
        end
    end

    options.on_stderr = function(err, data, job)
        -- FYI, with plenary.job, on_stdout/on_stderr are both called one last time (with nil data) after :shutdown is called... NBD just a reminder
        -- just log for now is fine
        info("on_stderr data: ", data, "err: ", err)
        if err then
            -- TODO stop abort?
        end
    end

    M.request = Job:new(options)
    M.request:start()
end

function M.stop_current_prediction()
    local this_prediction = M.current_prediction
    if not this_prediction then
        return
    end
    M.current_prediction = nil
    this_prediction:mark_as_abandoned() -- TODO maybe move clear_extmarks into here?

    vim.schedule(function()
        -- TODO is this where I want the schedule call? seems like a natural concern for the code here that interacts with a prediction process and results in streaming fashion
        this_prediction:clear_extmarks()
    end)

    -- FYI feels like this should be associated with Prediction (maybe not) => if I combine this with Prediction I'd just need one M.prediction global
    local request = M.request
    M.request = nil
    if request then
        info("Terminating prediction request")
        request:shutdown()
    end
end

-- separate the top level handlers -> keep these thin so I can distinguish the request from the work (above)
function M.cursor_moved_in_insert_mode()
    M.ask_for_prediction()
end

function M.leaving_insert_mode()
    M.stop_current_prediction()
end

function M.accept_all_invoked()
    info("Accepting all predictions...")
end

function M.accept_line_invoked()
    info("Accepting line prediction...")
end

function M.accept_word_invoked()
    info("Accepting word prediction...")
end

return M
