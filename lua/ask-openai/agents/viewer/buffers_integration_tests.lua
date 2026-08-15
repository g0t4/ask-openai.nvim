-- Integration test: simulate a long agent trace streaming into an on-screen
-- chat window (AgentWindow) to replicate the lag/lock-up seen on long traces.
--
-- The real chat viewer calls `replace_with_styled_lines_after(turn_start, lines)`
-- on *every* token, which rewrites the whole accumulated buffer (plus extmarks
-- and fold bookkeeping) from the turn start each time. On a long trace that is
-- O(n^2) and is the prime suspect for the freeze-ups.
--
-- This file provides `run_simulation()` which opens a real AgentWindow on-screen
-- and streams lines at ~token speed so you can watch for lag live. It works two
-- ways:
--   1. As a plenary/busted test (`make tests` or :PlenaryBustedFile) - a short run
--      that just sanity-checks nothing crashes.
--   2. Via the `<leader>abs` keymap (wired up in AgentsFrontend.setup) so you can
--      run it in your *current* nvim instance and see the window update live.
--      Edit the constants below, restart, hit the keymap, watch.
--
-- Stop early with <Esc> in the window. `mode = "replace"` replicates the real
-- per-token full-buffer rewrite; `mode = "append"` just appends (eliminates the
-- rewrite as a factor).

local M = {}

---@alias SimMode '"replace"' | '"append"'

-- Tweak these to stress-test different sizes/rates.
local DEFAULT_TOTAL_LINES = 2000 -- total lines streamed (long trace ballpark)
local DEFAULT_LINES_PER_WRITE = 2 -- lines appended per timer tick
local DEFAULT_WRITE_INTERVAL_MS = 4 -- ~250 tok/s with 1 line/tick

-- A small pool of long-ish filler lines (plain text, no styling) so the buffer
-- grows into something that looks like a real agent response.
local LOREM_LINES = {
    "The quick brown fox jumps over the lazy dog while the rain falls gently on the pavement outside the old library.",
    "Every great journey begins with a single step, but the bravest begin with a single leap into the unknown darkness.",
    "She counted the seconds between lightning and thunder, each gap shrinking as the storm marched relentlessly closer.",
    "The algorithm churned through thousands of records, discarding noise and surfacing the one signal that mattered.",
    "In the quiet hours before dawn, the city hums a low melody that only the most patient listeners can ever hear.",
    "A well-crafted abstraction hides the messy details behind a clean interface, trading immediacy for safety.",
    "The cursor blinked patiently, waiting for the next keystroke, for the next thought to spill onto the page.",
    "Refactoring is like gardening: you pull one weed and discover a tangled root system you never knew existed.",
    "The model generated token after token, each one nudging the probability of the next into sharper focus.",
    "Somewhere between the first draft and the final cut, the prose found its rhythm and stopped apologizing.",
}

--- Build a LinesBuilder containing all accumulated lines (reused ns_id so the
--- extmark namespace is created once per run, matching the real turn lifecycle).
---@param accumulated string[]
---@param marks_ns_id number
---@return table
local function build_full_turn_builder(accumulated, marks_ns_id)
    local LinesBuilder = require("ask-openai.agents.viewer.lines_builder")
    local builder = LinesBuilder:new(marks_ns_id)
    for _, line in ipairs(accumulated) do
        builder:append_line(line)
    end
    return builder
end

--- Run the long-trace buffer simulation in a real on-screen AgentWindow.
---@param opts? {
---   mode?: SimMode,             -- "replace" (real behavior) or "append"
---   lines_per_write?: number,   -- lines added per timer tick
---   write_interval_ms?: number, -- ms between ticks
---   total_lines?: number,       -- when to stop the simulation
---   turn_start_line_base0?: number, -- where each replace starts (default 0)
--- }
---@return table window The AgentWindow instance (holds _sim_timer / _sim_complete)
function M.run_simulation(opts)
    opts = opts or {}
    local mode = opts.mode or "replace" --[[@type SimMode]]
    local lines_per_write = opts.lines_per_write or DEFAULT_LINES_PER_WRITE
    local write_interval_ms = opts.write_interval_ms or DEFAULT_WRITE_INTERVAL_MS
    local total_lines = opts.total_lines or DEFAULT_TOTAL_LINES
    local turn_start_line_base0 = opts.turn_start_line_base0 or 0

    local AgentWindow = require("ask-openai.agents.viewer.window")

    -- Reuse the same buffer name as the real chat window so it looks identical.
    local window = AgentWindow:new()
    window.buffer:clear()
    window:mark_agent_running(true)
    window:ensure_spinner_running("SIMULATED LONG TRACE")
    window:open()

    local accumulated = {}  -- @type string[]
    local written_line_count = 0
    local marks_ns_id = vim.api.nvim_create_namespace("sim_long_trace")

    local timer = vim.loop.new_timer()
    window._sim_timer = timer
    window._sim_complete = false

    local started_at_ms = vim.uv.hrtime() / 1e6

    timer:start(0, write_interval_ms, vim.schedule_wrap(function()
        if not vim.api.nvim_win_is_valid(window.win_id) then
            -- window was closed mid-run; bail out cleanly
            timer:stop()
            timer:close()
            window._sim_complete = true
            return
        end

        for _ = 1, lines_per_write do
            written_line_count = written_line_count + 1
            local source = LOREM_LINES[(written_line_count - 1) % #LOREM_LINES + 1]
            table.insert(accumulated, string.format("%06d: %s", written_line_count, source))
        end

        if mode == "replace" then
            -- replicate the real per-token full-buffer rewrite from the turn start
            local builder = build_full_turn_builder(accumulated, marks_ns_id)
            window.buffer:replace_with_styled_lines_after(turn_start_line_base0, builder)
        else
            -- just append the newest chunk (eliminates the rewrite as a factor)
            local LinesBuilder = require("ask-openai.agents.viewer.lines_builder")
            local builder = LinesBuilder:new(marks_ns_id)
            for i = written_line_count - lines_per_write + 1, written_line_count do
                builder:append_line(accumulated[i])
            end
            window:append_styled_lines(builder)
        end

        local elapsed_s = ((vim.uv.hrtime() / 1e6) - started_at_ms) / 1000
        window._footer = string.format("lines: %d/%d | elapsed: %.1fs", written_line_count, total_lines, elapsed_s)
        window:rebuild_title()

        if written_line_count >= total_lines then
            timer:stop()
            timer:close()
            window:mark_agent_running(false)
            window._sim_complete = true
            window:stop_spinner(string.format("SIMULATION DONE - %d lines in %.1fs", written_line_count, elapsed_s))
        end
    end))

    -- <Esc> stops the simulation early (also works from insert mode).
    vim.keymap.set({ "n", "i" }, "<Esc>", function()
        timer:stop()
        timer:close()
        window:mark_agent_running(false)
        window._sim_complete = true
        window:stop_spinner(string.format("SIMULATION STOPPED - %d lines", written_line_count))
    end, { buffer = window.buffer_number })

    return window
end

-- Only register a plenary/busted test when running under the test harness.
-- (The devtools test globals don't exist in a normal nvim session, so requiring
-- this file from a keymap is safe and just exposes `run_simulation`.)
if _G.describe then
    require("ask-openai.helpers.test_setup").modify_package_path()

    describe("BufferController: simulated long trace (on-screen window)", function()
        it("streams many lines without erroring", function()
            local window = M.run_simulation({
                mode = "replace",
                lines_per_write = 2,
                write_interval_ms = 1,
                total_lines = 200, -- short run: just sanity-check it completes
            })

            local e2e = require("ask-openai.helpers.test_e2e")
            local done = e2e.wait_for(function()
                return window._sim_complete == true
            end, 15000, 50)

            assert.is_true(done, "simulation did not finish within the timeout")
        end)
    end)
end

return M
