local M = {}
local init = require("ask-openai")

function M.enable_predictions()
    init.start_predictions()
end

function M.disable_predictions()
    init.stop_predictions()
end

function M.is_enabled()
    return init.is_predictions_enabled()
end

return M
