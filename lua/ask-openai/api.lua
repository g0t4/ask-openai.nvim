local M = {}
local init = require("ask-openai.init")

function M.enable_predictions()
    init.predictions.enable()
end

function M.disable_predictions()
    init.predictions.disable()
end

function M.is_enabled()
    return init.predictions.is_enabled
end

return M
