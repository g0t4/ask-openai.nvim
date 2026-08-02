local rx = require("rx")
local TimeoutScheduler = require("ask-openai.rx.scheduler")
local M = {}

--- @alias ObservableKeyPressEvent { bufnr: integer }

--- @return Subject keypresses
--- @return Observable debounced
function M.create_keypresses_observables()
    local scheduler = TimeoutScheduler.create()
    local keypresses = rx.Subject.create()
    local debounced = keypresses:debounce(250, scheduler)
    return keypresses, debounced
end

return M
