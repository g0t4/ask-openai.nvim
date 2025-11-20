local rx = require 'rx'
local uv = vim.uv
local VimUvTimeoutScheduler = {}
VimUvTimeoutScheduler.__index = VimUvTimeoutScheduler
VimUvTimeoutScheduler.__tostring = 'TimeoutScheduler'

-- Based on:
--   https://github.com/bjornbytes/RxLua/tree/master/doc#timeoutscheduler
--   https://github.com/bjornbytes/RxLua/blob/master/src/schedulers/timeoutscheduler.lua
--     rxlua TimeoutScheduler is based on an outdated version of `luv`

function VimUvTimeoutScheduler.create()
    return setmetatable({}, VimUvTimeoutScheduler)
end

--- Schedules an action to run at a future point in time.
---@arg {function} action
---@arg {number=0} delay, in milliseconds.
---@returns {rx.Subscription} => IIUC is used to cancel the timer (i.e. if a source produces a new event before timer fires)
function VimUvTimeoutScheduler:schedule(action, delay_ms, ...)
    local packed_args = { ... }

    -- luv docs:
    --   uv_timer_start: https://github.com/luvit/luv/blob/master/deps/libuv/src/timer.c#L68
    --   uv.timer_start docs: https://github.com/luvit/luv/blob/master/docs.md#L771
    --      mentions milliseconds for both timeout and repeat
    --   setTimeout/setInterval/clearTimeout examples:
    --      https://github.com/luvit/luv/blob/master/examples/timers.lua

    self.timer = uv.new_timer()

    -- FYI TEST WITH:
    --     :Dump require("ask-openai.rx.scheduler").create():schedule(function() print "fuuuuu" end, 3000)
    --
    -- 3rd arg is repeat, and thus 0ms (not an interval)
    uv.timer_start(self.timer, delay_ms, 0, function()
        action(unpack(packed_args)) -- lua 5.1 is unpack (not table.unpack yet) => nvim is 5.1
    end)

    -- subscription allows observer to unsubscribe
    --  => subscription:unsubscribe
    function on_observer_unsubscribe()
        -- FYI TEST WITH:
        --     :Dump require("ask-openai.rx.scheduler").create():schedule(function() print "fuuuuu" end, 3000):unsubscribe()
        self.timer:stop()
    end

    return rx.Subscription.create(on_observer_unsubscribe)
end

return VimUvTimeoutScheduler
