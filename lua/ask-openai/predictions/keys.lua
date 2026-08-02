local rx = require("rx")
local TimeoutScheduler = require("ask-openai.rx.scheduler")
local M = {}

--- @alias ObservableInputEvent { bufnr: integer }

--- @return Subject input_events
--- @return Observable debounced
function M.create_input_observables()
    local scheduler = TimeoutScheduler.create()
    local input_events = rx.Subject.create()
    local debounced = input_events:debounce(250, scheduler)
    return input_events, debounced
end

return M
