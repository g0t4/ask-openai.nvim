local rx = require("rx")
local TimeoutScheduler = require("ask-openai.rx.scheduler")
local M = {}

local TYPING_DEBOUNCE_MS = 250
local TYPING_RESET_MS = 500

--- @alias ObservableInputEvent { bufnr: integer }

--- @return Subject input_events
--- @return Observable debounced
function M.global_create_debounced_observable()
    local scheduler = TimeoutScheduler.create()
    local input_events = rx.Subject.create()
    local debounced = input_events:debounce(250, scheduler)
    return input_events, debounced
end

---@param delay_ms? integer
---@return Subject input_events
---@return Observable debounced
function M.create_debounced_observable_by_bufnr(delay_ms)
    if delay_ms == nil then
        error("delay_ms must be provided")
    end

    local input_events = rx.Subject.create()
    local debounced = input_events:debounceByKey(
        function(ev)
            return ev.bufnr
        end,
        delay_ms,
        TimeoutScheduler.create
    )
    return input_events, debounced
end

--- Let the first event for each buffer through immediately, then debounce later
--- events until that buffer has been idle long enough to leave typing mode.
---@param delay_ms? integer
---@param reset_ms? integer
---@return Subject input_events
---@return Observable debounced
function M.create_typing_debounced_observable_by_bufnr(delay_ms, reset_ms)
    delay_ms = delay_ms or TYPING_DEBOUNCE_MS
    reset_ms = reset_ms or TYPING_RESET_MS

    if delay_ms >= reset_ms then
        error("delay_ms must be less than reset_ms")
    end

    local input_events = rx.Subject.create()
    local debounced = input_events:typingDebounceByKey(
        function(ev)
            return ev.bufnr
        end,
        delay_ms,
        reset_ms,
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

--- Immediately emit the first value for a key. While that key remains active,
--- debounce subsequent values. The key becomes inactive after resetDelay has
--- elapsed without input, independently of other keys.
function rx.Observable:typingDebounceByKey(keySelector, delay, resetDelay, schedulerFactory)
    return rx.Observable.create(function(observer)
        local states = {}

        return self:subscribe(
            function(value)
                local key = keySelector(value)
                local state = states[key]

                if state == nil then
                    state = {}
                    states[key] = state
                    observer:onNext(value)
                else
                    if state.debounceSubscription then
                        state.debounceSubscription:unsubscribe()
                    end

                    local debounceScheduler = schedulerFactory()
                    state.debounceSubscription = debounceScheduler:schedule(function()
                        state.debounceSubscription = nil
                        observer:onNext(value)
                    end, delay)
                end

                if state.resetSubscription then
                    state.resetSubscription:unsubscribe()
                end

                local resetScheduler = schedulerFactory()
                state.resetSubscription = resetScheduler:schedule(function()
                    states[key] = nil
                end, resetDelay)
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
