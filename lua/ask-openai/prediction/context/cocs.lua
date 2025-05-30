-- I want to take that completion list from coc and feed it into the model too
--  that way the model can select from that list so I don't have to scroll down
--  and this is highly tailored to the context at hand...
--  and then I need to determine if this meaningfully helps with predictions
--    i.e. write a test suite, capture examples as I use coc where it would be nice for the model to pick the completion
--    wait... could I race a second completion with JUST coc current items...
--      and then maybe use that to auto highlight (not select) that item so I can hit enter to accept it?)
--      or ask for a confidence score and have it switch to that vs regular predictions?
--  could look into only passing this list if I switch on a mode to do so
--    i.e. advanced predictions that take longer but consider more context like coc, recent edtis, clipboard history, etc

-- TODO find out how to programatically access the list of completions shown by coc in the menu and pass to the model

local M = {}

function M.setup()
end

return M
