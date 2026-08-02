-- testing modules:
require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require('luassert')
local should = require("devtools.tests.should")
local debouncing = require("ask-openai.rx.debouncing")

describe("Observable:debounceByKey", function()
    describe("integration tests", function()
        it("multiple events per bufnr, returns last per bufnr", function()
            local input_events, debounced_by_bufnr = debouncing.create_debounced_observable_by_bufnr(50)

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
            vim.wait(10) -- keep in mind vim.wait is not precise
            assert.same({}, received)
            vim.wait(10)
            assert.same({}, received)
            vim.wait(10) -- I wouldn't try to be more precise than 30ms delay here and still empty, test ops are not zero duration
            assert.same({}, received)
            vim.wait(40) -- well past
            assert.same({
                { bufnr = 1, value = 'i' },
                { bufnr = 2, value = 'b' },
            }, received)
        end)

        it("does not allow one bufnr to debounce another", function()
            local input_events, debounced_by_bufnr = debouncing.create_debounced_observable_by_bufnr(50)

            local received = {}

            debounced_by_bufnr:subscribe(function(event)
                table.insert(received, event)
            end)

            -- Start debounce for bufnr 1.
            input_events:onNext({ bufnr = 1, value = "a" })

            local IS_EMPTY = {}
            vim.wait(30)
            --- 30ms total for bufnr 1
            assert.same(IS_EMPTY, received)

            -- This should NOT reset bufnr 1's debounce timer.
            input_events:onNext({ bufnr = 2, value = "x" })
            assert.same(IS_EMPTY, received)

            vim.wait(30)
            -- 60ms total for bufnr 1, but only 30ms from bufnr 2.
            assert.same({ { bufnr = 1, value = "a" }, }, received)

            vim.wait(30)
            -- 60ms total for bufnr 2

            assert.same({
                { bufnr = 1, value = "a" },
                { bufnr = 2, value = "x" },
            }, received)
        end)
    end)
end)
