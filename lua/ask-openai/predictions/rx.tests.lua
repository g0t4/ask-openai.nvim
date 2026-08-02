-- testing modules:
require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require 'luassert'
local rx = require "rx"

local debounced = require("ask-openai.predictions.rx")

local function create_fake_scheduler()
    local scheduled = {}

    local scheduler = {}

    function scheduler:schedule(action, delay_ms)
        local task = {
            action = action,
            delay_ms = delay_ms,
            cancelled = false,
        }

        table.insert(scheduled, task)

        return rx.Subscription.create(function()
            task.cancelled = true
        end)
    end

    local function flush()
        local pending = scheduled
        scheduled = {}

        for _, task in ipairs(pending) do
            if not task.cancelled then
                task.action()
            end
        end
    end

    return scheduler, flush
end

describe("Observable:debounceByKey", function()
    it("debounces independently for each key", function()
        local scheduler, flush = create_fake_scheduler()
        local source = rx.Subject.create()
        local received = {}

        source
            :debounceByKey(function(event)
                return event.bufnr
            end, 250, function()
                return scheduler
            end)
            :subscribe(function(event)
                table.insert(received, event)
            end)

        source:onNext({ bufnr = 1, value = "buffer 1 first" })
        source:onNext({ bufnr = 2, value = "buffer 2" })
        source:onNext({ bufnr = 1, value = "buffer 1 latest" })

        flush()

        assert.same({
            { bufnr = 2, value = "buffer 2" },
            { bufnr = 1, value = "buffer 1 latest" },
        }, received)
    end)
end)
