local M = {}
local init = require("ask-openai")
local config = require("ask-openai.config")
local lualine = require('ask-openai.status.lualine')
local LlamaServerClient = require('ask-openai.backends.llama_cpp.llama_server_client')

-- cache for model names per base url (host:port)
local _model_cache = {}

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
function M.set_fim_reasoning_level(level)
    config.local_share.set_fim_reasoning_level(level)
end

-- Set the reasoning level for the Rewrite frontend (separate from the universal setting).
function M.set_rewrite_reasoning_level(level)
    config.local_share.set_rewrite_reasoning_level(level)
end

function M.get_fim_reasoning_level()
    return config.local_share.get_fim_reasoning_level()
end

function M.get_rewrite_reasoning_level()
    return config.local_share.get_rewrite_reasoning_level()
end

function M.cycle_fim_reasoning_level()
    return config.local_share.cycle_fim_reasoning_level()
end

function M.cycle_rewrite_reasoning_level()
    return config.local_share.cycle_rewrite_reasoning_level()
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
function M.get_lualine_components()
    return lualine.lualine_components()
end

function M.get_lualine_status()
    return {
        function() return "PLEASE SWITCH TO api.lualine_components()" end,
        color = function()
            return {
                bg = '#FF0000',
                fg = '#FFFFFF',
                gui = 'bold'
            }
        end
    }
end

--- Query the llama-server for the model name running at the given base URL.
--- Uses the `/v1/models` endpoint and caches the result per URL.
--- @param base_url string The base URL of the llama-server (e.g. "http://paxy.lan:8012")
--- @return string|nil The model name if discovered, otherwise nil.
function M.get_llama_server_model(base_url)
    if _model_cache[base_url] ~= nil then
        return _model_cache[base_url]
    end

    local response = LlamaServerClient.get_models(base_url)
    if not response or response.code ~= 200 then
        return nil
    end

    local body = response.body
    local model_name = nil
    if type(body) == "table" then
        if body.data and #body.data > 0 then
            local first = body.data[1]
            if type(first) == "table" and first.id then
                model_name = first.id
            end
        elseif body.id then
            model_name = body.id
        end
    end

    _model_cache[base_url] = model_name
    return model_name
end

return M
