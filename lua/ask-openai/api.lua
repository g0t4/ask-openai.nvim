local M = {}
local init = require("ask-openai")
local config = require("ask-openai.config")
local lualine = require('ask-openai.status.lualine')

-- * predictions *
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

-- * verbose logs *
function M.cycle_log_verbosity()
    return config.local_share.cycle_log_verbosity()
end

-- * FIM model *
function M.set_fim_model(model)
    config.local_share.set_fim_model(model)
end

function M.get_fim_model()
    return config.local_share.get_fim_model()
end

function M.toggle_fim_model()
    config.local_share.toggle_fim_model()
end

-- * reasoning level (universal - FIM, Ask*)
function M.set_reasoning_level(level)
    config.local_share.set_reasoning_level(level)
end

function M.get_reasoning_level()
    return config.local_share.get_reasoning_level()
end

function M.cycle_reasoning_level()
    return config.local_share.cycle_reasoning_level()
end

-- * notify stats *
function M.toggle_notify_stats()
    config.local_share.toggle_notify_stats()
end

function M.are_notify_stats_enabled()
    return config.local_share.are_notify_stats_enabled()
end

-- * rag *
function M.toggle_rag()
    config.local_share.toggle_rag()
    -- FOR NOW LSP won't be stopped/started on toggling RAG flag
    --  and actually, it may not ever make sense to stop it given if RAG is disabled then it won't be used for queries
    if M.is_rag_enabled() then
        print("restart nvim to ensure LSP is stopped")
    else
        print("restart nvim to ensure LSP is running")
    end
end

function M.is_rag_enabled()
    return config.local_share.is_rag_enabled()
end

---@return table components
function M.get_lualine_status()
    return lualine.lualine()
end

return M
