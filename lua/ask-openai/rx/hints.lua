local rx = require 'rx'
local TimeoutScheduler = require("ask-openai.rx.scheduler")
local M = {}

-- hints from user that they want to see predictions
--   PRN anything besides keystrokes (i.e. enter insert mode though that is keystroke too)
--   will debounce and filter this as needed to make Ux responsive
--   w/o this every keystroke => gen request => cancel previous request (thrashing needlessly)
--   also would be nice to configure delays in some situations...
--      i.e. how about make immediate request on first hint in a period of time (i.e. after quiescent period)
--          then, after I continue hints (i.e. typing) then wait for a debounce period (after say 250ms of no more typing or other hints)
function M.keystrokesObservable(delay_ms)
    delay_ms = delay_ms or 250

    -- TODO MOVE THIS OUT... I don't need this anymore (just let consumers handle both parts...)

    local scheduler = TimeoutScheduler.create()
    -- todo turn into "type" and use self.keypresses so I can make outer methods to trigger the subject
    local keypresses = rx.Subject.create()

    local debounced = keypresses:debounce(delay_ms, scheduler)

    -- TODO how about use a class/type in lua to store these on self:
    -- self.keypresses = keypresses
    -- self.debounced = debounced
    -- then add :methods() to do things
    return keypresses, debounced
    -- I need to return access to both the debounced observable AND keypresses subject... UNLESS MAYBE I SHOULD SPLIT THESE UP

    -- SUBJECTS:
    -- example of pushing values (b/c its a subject, too):
    -- moves:onNext({ x = 0, y = 0 })
    -- moves:onCompleted()
    -- moves:onError("fuuuuu") -- never received b/c commplete already called
end

return M
