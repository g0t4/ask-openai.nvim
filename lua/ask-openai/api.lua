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
    if config.local_share.are_predictions_enabled() then
        M.disable_predictions()
    else
        M.enable_predictions()
    end
end

function M.are_predictions_enabled()
    return config.local_share.are_predictions_enabled()
end

function M._setup()
    -- FYI underscore in _setup is to indicate this is internal use only, won't hurt if users call it again though

    vim.api.nvim_create_user_command('AskTogglePredictions', function()
        M.toggle_predictions()
    end, {})

    vim.api.nvim_create_user_command('AskStatus', function()
        if M.are_predictions_enabled() then
            print('Ask predictions enabled')
        else
            print('Ask predictions disabled')
        end
    end, {})
end

return M
