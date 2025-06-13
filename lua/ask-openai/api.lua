local M = {}
local init = require("ask-openai")
local config = require("ask-openai.config")

function M.enable_predictions()
    config.local_share.set_predictions_on()
    init.start_predictions()
end

function M.disable_predictions()
    config.local_share.set_predictions_off()
    init.stop_predictions()
end

function M.is_enabled()
    return config.local_share.is_predictions_enabled()
end

return M
