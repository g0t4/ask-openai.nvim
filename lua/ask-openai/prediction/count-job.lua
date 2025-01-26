-- TODO make this work in future if I want it again... just a reminder really
function M.simulate_count_as_prediction()
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
    local Job = require("plenary.job")

    -- JOB simulates getting a stream of results (1 to 10) - FYI no new lines
    local options = {
        command = "fish",
        args = {
            "-c",
            -- SIMULATE STREAMING response:
            "for i in (seq 1 10); echo $i; sleep 0.5; end"
            -- "echo foo && sleep 2 && echo bar",
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

    options.on_stdout = function(err, data, job)
        -- on_stdout signature: https://github.com/nvim-lua/plenary.nvim/blob/3707cdb1e43f5cea73afb6037e6494e7ce847a66/lua/plenary/job.lua#L18
        info("on_stdout data: ", data, "err: ", err)
        -- FYI, with plenary.job, on_stdout/on_stderr are both called one last time (with nil data) after :shutdown is called... NBD just a reminder
        if err then
            this_prediction:generation_failed()
            return
        end

        if data then
            vim.schedule(function()
                local joined_lines = data:gsub("\n", "") -- for now strip new lines ... do not do this with SSE parsing
                this_prediction:add_chunk_to_prediction(joined_lines)
            end)
        end
    end

    options.on_stderr = function(err, data, job)
        -- https://github.com/nvim-lua/plenary.nvim/blob/3707cdb1e43f5cea73afb6037e6494e7ce847a66/lua/plenary/job.lua#L19

        -- FYI, with plenary.job, on_stdout/on_stderr are both called one last time (with nil data) after :shutdown is called... NBD just a reminder
        -- just log for now is fine
        info("on_stderr data: ", data, "err: ", err)
        if err then
            -- TODO? not sure I need to mark any failures here
            -- return
        end
        if data then
            -- TODO consider reactions needed in the future
        end
    end

    M.request = Job:new(options)
    M.request:start()
end
