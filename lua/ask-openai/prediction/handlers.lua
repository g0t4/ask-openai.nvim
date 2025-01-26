local uv = vim.uv
local M = {}
local Prediction = require("ask-openai.prediction.prediction")

-- FYI would need current prediction PER buffer in the future if want multiple buffers to have predictions at same time (not sure I want this feature)
M.current_prediction = nil -- set on module for now, just so I can inspect it easily

-- FYI useful to observe what is happening under hood, run in pane below nvim (don't need to esc and look at :messages)
--    tail -f /Users/wesdemos/.local/share/nvim/ask/ask-predictions.log
M.logger = require("ask-openai.prediction.logger"):new("ask-predictions.log")
local function info(...)
    -- TODO use top level config or a new setting to turn on/off
    M.logger:log(...)
end

function M.ask_for_prediction()
    info("Asking for prediction...")
    M.stop_current_prediction()

    -- TODO use plenary.job/curl (has builtin support for streaming!)
    --  job:
    --      docs: https://github.com/nvim-lua/plenary.nvim?tab=readme-ov-file#plenaryjob
    --      code: https://github.com/nvim-lua/plenary.nvim/blob/master/lua/plenary/job.lua
    --  curl:
    --      docs: https://github.com/nvim-lua/plenary.nvim?tab=readme-ov-file#plenarycurl
    --      code: https://github.com/nvim-lua/plenary.nvim/blob/master/lua/plenary/curl.lua
    --  async:
    --      docs: https://github.com/nvim-lua/plenary.nvim/blob/master/README.md#plenaryasync
    --      generalized async support - base of job/curl features

    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)
    local command = "fish"

    -- closure captures this id for any callbacks to use to ignore past predictions
    local this_prediction = Prediction:new()
    M.current_prediction = this_prediction

    local args = {
        "-c",
        -- SIMULATE STREAMING response:
        "for i in (seq 1 10); echo $i; sleep 0.5; end"
        -- "echo foo && sleep 2 && echo bar",
    }

    M.handle, M.pid = uv.spawn(command, {
        args = args,
        stdio = { nil, stdout, stderr },
    }, function(code, signal)
        info("Exit code:", code, "Signal:", signal)
        stdout:close()
        stderr:close()
    end)

    uv.read_start(stdout, function(err, data)
        assert(not err, err)
        if data then
            info("STDOUT:", data)
            vim.schedule(function()
                local first_data_line_only = data:match("^(.-)\n")
                this_prediction:add_chunk_to_prediction(first_data_line_only)
            end)
        end
    end)

    uv.read_start(stderr, function(err, data)
        assert(not err, err)
        if data then
            info("stderr:", data)
            this_prediction:add_chunk_to_prediction("STDERR: " .. data)
            -- TODO consider reactions needed in the future
        end
    end)
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

    if M.handle and not M.handle:is_closing() then
        info("Terminating process, pid: ", M.pid)
        M.handle:kill("sigterm") -- Send SIGTERM to the process
        M.handle:close()         -- Close the handle
        -- TODO what if kill fails? how do I mark this prediction as discard it?
        --   or before it terminates, if another chunk arrives... I should track a request_id (guid) and use that to ignore if data still arrives after I request termination
        --   and before it terminates I start another request... which I want for responsiveness
        --
        M.handle = nil
        M.pid = nil
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
