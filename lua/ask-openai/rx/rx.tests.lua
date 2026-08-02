-- testing modules:
require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require('luassert')
local should = require("devtools.tests.should")
local rx = require "rx"

local ask_rx = require("ask-openai.rx.rx")

local function create_fake_scheduler()
    -- FYI this fake scehduler may be useful but it makes it very hard to assert debounce which is inherently time based... maybe if you setup a simulated clock this would make more sense but yeah no on this fake scheduler for time based Rx verification
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
    describe("fake scheduler", function()
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

    describe("integration tests", function()
        it("multiple events per bufnr, returns last per bufnr", function()
            local input_events, debounced_by_bufnr = ask_rx.create_debounced_observable_by_bufnr()

            local received = {}

            debounced_by_bufnr:subscribe(function(event)
                table.insert(received, event)
            end)

            -- bufnr1
            input_events:onNext({ bufnr = 1, value = 't' })
            input_events:onNext({ bufnr = 1, value = 'y' })
            input_events:onNext({ bufnr = 1, value = 'p' })
            input_events:onNext({ bufnr = 1, value = 'i' })

            -- bufnr2
            input_events:onNext({ bufnr = 2, value = 'a' })
            input_events:onNext({ bufnr = 2, value = 'b' })


            assert.same({}, received)
            vim.wait(100)
            assert.same({}, received)
            vim.wait(100)
            assert.same({}, received)
            vim.wait(100) -- well past 250ms debounce period
            assert.same({
                { bufnr = 1, value = 'i' },
                { bufnr = 2, value = 'b' },
            }, received)
        end)

        it("does not allow one bufnr to debounce another", function()
            local input_events, debounced_by_bufnr = ask_rx.create_debounced_observable_by_bufnr()

            local received = {}

            debounced_by_bufnr:subscribe(function(event)
                table.insert(received, event)
            end)

            -- Start debounce for bufnr 1.
            input_events:onNext({ bufnr = 1, value = "a" })

            local IS_EMPTY = {}
            vim.wait(150)
            --- 150ms total for bufnr 1
            assert.same(IS_EMPTY, received)

            -- This should NOT reset bufnr 1's debounce timer.
            input_events:onNext({ bufnr = 2, value = "x" })
            assert.same(IS_EMPTY, received)

            vim.wait(150)
            -- 300ms total for bufnr 1, but only 150ms from bufnr 2.
            assert.same({ { bufnr = 1, value = "a" }, }, received)

            vim.wait(150)
            -- 300ms total for bufnr 2

            assert.same({
                { bufnr = 1, value = "a" },
                { bufnr = 2, value = "x" },
            }, received)
        end)
    end)
end)
