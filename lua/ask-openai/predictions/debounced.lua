local rx = require("rx")
local TimeoutScheduler = require("ask-openai.rx.scheduler")
local M = {}

--- @alias ObservableInputEvent { bufnr: integer }

--- @return Subject input_events
--- @return Observable debounced
function M.global_create_debounced_observable()
    local scheduler = TimeoutScheduler.create()
    local input_events = rx.Subject.create()
    local debounced = input_events:debounce(250, scheduler)
    return input_events, debounced
end

--- @return Subject input_events
--- @return Observable debounced
function M.create_debounced_observable_by_bufnr()
    local input_events = rx.Subject.create()
    local debounced = input_events:debounceByKey(
        function(ev)
            return ev.bufnr
        end,
        250,
        TimeoutScheduler.create
    )
    return input_events, debounced
end

function rx.Observable:debounceByKey(keySelector, delay, schedulerFactory)
    return rx.Observable.create(function(observer)
        local subscriptions = {}

        return self:subscribe(
            function(value)
                local key = keySelector(value)

                local subscription = subscriptions[key]
                if subscription then
                    subscription:unsubscribe()
                end

                local scheduler = schedulerFactory()

                subscriptions[key] = scheduler:schedule(function()
                    subscriptions[key] = nil
                    observer:onNext(value)
                end, delay)
            end,
            function(err)
                observer:onError(err)
            end,
            function()
                observer:onCompleted()
            end
        )
    end)
end

return M
