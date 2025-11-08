local M = {}
local init = require("ask-openai")
local config = require("ask-openai.config")

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
function M.toggle_verbose_logs()
    config.local_share.toggle_verbose_logs()
end

function M.are_verbose_logs_enabled()
    return config.local_share.are_verbose_logs_enabled()
end

function M.set_fim_model(model)
    config.local_share.set_fim_model(model)
end

function M.get_fim_model()
    return config.local_share.get_fim_model()
end

function M.toggle_fim_model()
    local current = config.local_share.get_fim_model()
    local next_model = (current == "codellama") and "deepseek-coder-v2" or "codellama"
    config.local_share.set_fim_model(next_model)
    return next_model
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

return M
