local M = {}
local init = require("ask-openai")
local config = require("ask-openai.config")
local logger = require("ask-openai.prediction.logger")

-- FYI uses can add commands if that's what they want, they have the API to do so:

function M.enable_predictions()
    config.local_share.set_predictions_enabled()
    init.start_predictions()
end

function M.disable_predictions()
    config.local_share.set_predictions_disabled()
    init.stop_predictions()
end

function M.toggle_predictions()
    if config.local_share.are_predictions_enabled() then
        M.disable_predictions()
    else
        M.enable_predictions()
    end
end

function M.are_predictions_enabled()
    return config.local_share.are_predictions_enabled()
end

function M.toggle_verbose_logs()
    config.local_share.toggle_verbose_logs()
end

function M.are_verbose_logs_enabled()
    return config.local_share.are_verbose_logs_enabled()
end

return M
