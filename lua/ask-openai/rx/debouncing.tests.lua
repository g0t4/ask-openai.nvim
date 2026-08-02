-- testing modules:
require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require('luassert')
local should = require("devtools.tests.should")
local debouncing = require("ask-openai.rx.debouncing")

describe("Observable:debounceByKey", function()
    describe("integration tests", function()
        it("multiple events per bufnr, returns last per bufnr", function()
            local input_events, debounced_by_bufnr = debouncing.create_debounced_observable_by_bufnr(50)

            local emitted = {}

            debounced_by_bufnr:subscribe(function(event)
                table.insert(emitted, event)
            end)

            -- bufnr1
            input_events:onNext({ bufnr = 1, value = 't' })
            input_events:onNext({ bufnr = 1, value = 'y' })
            input_events:onNext({ bufnr = 1, value = 'p' })
            input_events:onNext({ bufnr = 1, value = 'i' })

            -- bufnr2
            input_events:onNext({ bufnr = 2, value = 'a' })
            input_events:onNext({ bufnr = 2, value = 'b' })


            assert.same({}, emitted)
            vim.wait(10) -- keep in mind vim.wait is not precise
            assert.same({}, emitted)
            vim.wait(10)
            assert.same({}, emitted)
            vim.wait(10) -- I wouldn't try to be more precise than 30ms delay here and still empty, test ops are not zero duration
            assert.same({}, emitted)
            vim.wait(40) -- well past
            assert.same({
                { bufnr = 1, value = 'i' },
                { bufnr = 2, value = 'b' },
            }, emitted)
        end)

        it("does not allow one bufnr to debounce another", function()
            local input_events, debounced_by_bufnr = debouncing.create_debounced_observable_by_bufnr(50)

            local emitted = {}

            debounced_by_bufnr:subscribe(function(event)
                table.insert(emitted, event)
            end)

            -- Start debounce for bufnr 1.
            input_events:onNext({ bufnr = 1, value = "a" })

            local IS_EMPTY = {}
            vim.wait(30)
            --- 30ms total for bufnr 1
            assert.same(IS_EMPTY, emitted)

            -- This should NOT reset bufnr 1's debounce timer.
            input_events:onNext({ bufnr = 2, value = "x" })
            assert.same(IS_EMPTY, emitted)

            vim.wait(30)
            -- 60ms total for bufnr 1, but only 30ms from bufnr 2.
            assert.same({ { bufnr = 1, value = "a" }, }, emitted)

            vim.wait(30)
            -- 60ms total for bufnr 2

            assert.same({
                { bufnr = 1, value = "a" },
                { bufnr = 2, value = "x" },
            }, emitted)
        end)
    end)
end)

describe("Observable:typingDebounceByKey", function()
    describe("integration tests", function()
        it("immediately returns the first event, then the last event from typing debounce interval (per bufnr)", function()
            local input_events, typing_debounced =
                debouncing.create_typing_debounced_observable_by_bufnr(50, 100)
            local emitted = {}

            typing_debounced:subscribe(function(event)
                table.insert(emitted, event)
            end)

            -- no delay on first keystroke for bufnr=1 (first buffer)
            input_events:onNext({ bufnr = 1, value = "t" })
            assert.same({ { bufnr = 1, value = "t" } }, emitted)

            -- typing debounce period, all are debounced until no more for delay_ms
            input_events:onNext({ bufnr = 1, value = "y" })
            input_events:onNext({ bufnr = 1, value = "p" })
            input_events:onNext({ bufnr = 1, value = "i" })
            assert.same({ { bufnr = 1, value = "t" } }, emitted)

            -- no delay on first keystroke for bufnr=2
            input_events:onNext({ bufnr = 2, value = "a" })
            assert.same({
                { bufnr = 1, value = "t" },
                { bufnr = 2, value = "a" },
            }, emitted)

            -- second keystroke for bufnr=2 (debounced 50ms)
            input_events:onNext({ bufnr = 2, value = "b" })
            vim.wait(30)
            -- so 30ms later it is not yet done waiting
            assert.same({
                { bufnr = 1, value = "t" },
                { bufnr = 2, value = "a" },
            }, emitted)
            vim.wait(20)
            -- now we've past 50ms debounce delay for both bufnrs ... so last keys should now be emitted
            assert.same({
                { bufnr = 1, value = "t" },
                { bufnr = 2, value = "a" },
                { bufnr = 1, value = "i" },
                { bufnr = 2, value = "b" },
            }, emitted)
        end)

        it("does not allow one bufnr to debounce or reset another", function()
            local input_events, typing_debounced =
                debouncing.create_typing_debounced_observable_by_bufnr(50, 100)
            local emitted = {}

            typing_debounced:subscribe(function(event)
                table.insert(emitted, event)
            end)

            input_events:onNext({ bufnr = 1, value = "a" })
            input_events:onNext({ bufnr = 1, value = "b" })
            vim.wait(30)

            input_events:onNext({ bufnr = 2, value = "x" })
            assert.same({
                { bufnr = 1, value = "a" },
                { bufnr = 2, value = "x" },
            }, emitted)

            vim.wait(20) -- right at the delay_ms for bufnr = 1 (emits b)
            assert.same({
                { bufnr = 1, value = "a" },
                { bufnr = 2, value = "x" },
                { bufnr = 1, value = "b" },
            }, emitted)

            -- Buffer 1 has reset, while buffer 2 is still in typing mode.
            vim.wait(50)
            input_events:onNext({ bufnr = 1, value = "c" }) -- no delay
            input_events:onNext({ bufnr = 2, value = "y" }) -- debounced (never goes through)
            input_events:onNext({ bufnr = 2, value = "z" }) -- last key during debounce delay_ms
            assert.same({
                { bufnr = 1, value = "a" },
                { bufnr = 2, value = "x" },
                { bufnr = 1, value = "b" },
                { bufnr = 1, value = "c" }, -- no delay
            }, emitted)

            vim.wait(50)
            assert.same({
                -- FYI you could add a label to the emitted events, i.e. `no_delay` and `last_in_debounce` ... that said, tests work too!
                { bufnr = 1, value = "a" }, -- no delay
                { bufnr = 2, value = "x" }, -- no delay
                { bufnr = 1, value = "b" },
                { bufnr = 1, value = "c" }, -- no delay
                { bufnr = 2, value = "z" }, -- last for bufnr = 2
            }, emitted)
        end)

        it("stays in typing mode until the full reset period has elapsed without input", function()
            local input_events, typing_debounced =
                debouncing.create_typing_debounced_observable_by_bufnr(50, 100)
            local emitted = {}

            typing_debounced:subscribe(function(event)
                table.insert(emitted, event)
            end)

            input_events:onNext({ bufnr = 1, value = "a" })
            input_events:onNext({ bufnr = 1, value = "b" })
            vim.wait(60) -- The debounced value has fired, but reset has not.
            input_events:onNext({ bufnr = 1, value = "c" })

            assert.same({
                { bufnr = 1, value = "a" },
                { bufnr = 1, value = "b" },
            }, emitted)

            vim.wait(30)
            assert.same({
                { bufnr = 1, value = "a" },
                { bufnr = 1, value = "b" },
            }, emitted)

            vim.wait(40)
            assert.same({
                { bufnr = 1, value = "a" },
                { bufnr = 1, value = "b" },
                { bufnr = 1, value = "c" },
            }, emitted)
        end)

        it("immediately returns the next event after reset", function()
            local input_events, typing_debounced =
                debouncing.create_typing_debounced_observable_by_bufnr(50, 100)
            local emitted = {}

            typing_debounced:subscribe(function(event)
                table.insert(emitted, event)
            end)

            input_events:onNext({ bufnr = 1, value = "a" })
            input_events:onNext({ bufnr = 1, value = "b" })
            vim.wait(120)
            input_events:onNext({ bufnr = 1, value = "c" })

            assert.same({
                { bufnr = 1, value = "a" },
                { bufnr = 1, value = "b" },
                { bufnr = 1, value = "c" },
            }, emitted)
        end)
    end)
end)
