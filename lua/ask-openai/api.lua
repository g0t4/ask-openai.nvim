local M = {}
local init = require("ask-openai")
local config = require("ask-openai.config")

function M.enable_predictions()
    config.local_share.set_predictions_enabled()
    init.start_predictions()
end

function M.disable_predictions()
    config.local_share.set_predictions_disabled()
    init.stop_predictions()
end

function M.toggle_predictions()
    local enabled = config.local_share.toggle_predictions()
    print('Ask Predictions ' .. (enabled and 'enabled' or 'disabled'))
end

function M.are_predictions_enabled()
    return config.local_share.are_predictions_enabled()
end

return M
