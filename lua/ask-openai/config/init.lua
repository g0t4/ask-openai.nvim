local local_share = require("ask-openai.config.local_share")
local models = require("ask-openai.config.models")

local M = {}

-- Latest discovery snapshot; refreshed only at startup or model selection.
local discovery = require("ask-openai.backends.discovery")

function M.refresh_endpoint_model_info(base_url, callback)
    if base_url then discovery.refresh(base_url, callback) end
end

-- Reads discovery for an endpoint; never selects model params or starts a request.
function M.get_endpoint_model_info(base_url, callback)
    discovery.when_ready(base_url, callback)
end

---@class AskOpenAIOptions
local default_options = {}

local cached_options = default_options

---@return AskOpenAIOptions
function M.get_options()
    return cached_options
end

--- @class Endpoint
--- @field base_url string

---@return table<string, Endpoint>
function M.get_endpoints()
    local gptoss_url = "http://build21.lan:8013"
    local qwen3_url = "http://build21.lan:8012"
    local gemma4_url = "http://build21.lan:8011"
    local glm_url = "http://ask.lan:8010"
    local deepseek_url = "http://ask.lan:8014"
    local muse_url = "http://build21.lan:8016"
    local nemo_lightning_url = "http://build21.lan:8017"

    -- FYI fine by me to collapse Endpoint into a string
    -- I used to handle name here too but that became a hot mess due to async vs sync
    -- sync is needed for endpoint URL...
    -- async is fine for name (for all my use cases thus far
    return {
        cmdline = {
            base_url = gptoss_url,
        },
        [models.QWEN] = {
            base_url = qwen3_url,
        },
        [models.DEEPSEEK] = {
            base_url = deepseek_url,
        },
        [models.GPTOSS] = {
            base_url = gptoss_url,
        },
        [models.GEMMA4] = {
            base_url = gemma4_url,
        },
        [models.GLM] = {
            base_url = glm_url,
        },
        [models.MUSE] = {
            base_url = muse_url,
        },
        [models.NEMO] = {
            base_url = nemo_lightning_url,
        },
    }
end

---@param config_model ConfigModel|string @Routing/configuration key, never an actual model name
function M.get_base_url(config_model)
    local endpoints = M.get_endpoints()
    -- Accept selections saved before the DeepSeek slug was renamed.
    if config_model == "deepseek" then config_model = models.DEEPSEEK end
    if endpoints[config_model] then
        return endpoints[config_model].base_url
    end
    return nil
end

function M.setup()
    local_share.setup()
    vim.schedule(function()
        local seen = {}
        for _, endpoint in pairs(M.get_endpoints()) do
            if not seen[endpoint.base_url] then
                seen[endpoint.base_url] = true
                M.refresh_endpoint_model_info(endpoint.base_url)
            end
        end
    end)
end

M.local_share = local_share

-- Model selectors below return config_model keys: endpoint routing, params, and
-- reasoning settings. Discovered actual_model names are display/diagnostic data.

-- * Agents model *
---@param config_model string
function M.set_agents_model(config_model)
    M.local_share.set_agents_model(config_model)
    M.refresh_endpoint_model_info(M.get_base_url(config_model))
end

---@return string
function M.get_agents_model()
    return M.local_share.get_agents_model()
end

---@return string
function M.toggle_agents_model()
    local config_model = M.local_share.toggle_agents_model()
    M.refresh_endpoint_model_info(M.get_base_url(config_model))
    return config_model
end

-- * FIM model *
---@param config_model string
function M.set_fim_model(config_model)
    M.local_share.set_fim_model(config_model)
    M.refresh_endpoint_model_info(M.get_base_url(config_model))
end

---@return string
function M.get_fim_model()
    return M.local_share.get_fim_model()
end

---@return string
function M.toggle_fim_model()
    local config_model = M.local_share.toggle_fim_model()
    M.refresh_endpoint_model_info(M.get_base_url(config_model))
    return config_model
end

-- * Rewrite model *
---@param config_model string
function M.set_rewrite_model(config_model)
    M.local_share.set_rewrite_model(config_model)
    M.refresh_endpoint_model_info(M.get_base_url(config_model))
end

---@return string
function M.get_rewrite_model()
    return M.local_share.get_rewrite_model()
end

---@return string
function M.toggle_rewrite_model()
    local config_model = M.local_share.toggle_rewrite_model()
    M.refresh_endpoint_model_info(M.get_base_url(config_model))
    return config_model
end

-- * predictions *
function M.enable_predictions()
    M.local_share.set_predictions_enabled()
    require("ask-openai.predictions.frontend").start_predictions()
end

function M.disable_predictions()
    M.local_share.set_predictions_disabled()
    require("ask-openai.predictions.frontend").stop_predictions()
end

function M.toggle_predictions()
    if M.local_share.are_predictions_enabled() then
        M.disable_predictions()
    else
        M.enable_predictions()
    end
end

function M.are_predictions_enabled()
    return M.local_share.are_predictions_enabled()
end

-- * reasoning level (universal - FIM, Ask*)
function M.set_fim_reasoning_level(level)
    M.local_share.set_fim_reasoning_level(level)
end

function M.set_rewrite_reasoning_level(level)
    M.local_share.set_rewrite_reasoning_level(level)
end

function M.set_agents_reasoning_level(level)
    M.local_share.set_agents_reasoning_level(level)
end

function M.get_fim_reasoning_level()
    return M.local_share.get_fim_reasoning_level()
end

function M.get_rewrite_reasoning_level()
    return M.local_share.get_rewrite_reasoning_level()
end

function M.get_agents_reasoning_level()
    return M.local_share.get_agents_reasoning_level()
end

function M.cycle_fim_reasoning_level()
    return M.local_share.cycle_fim_reasoning_level()
end

function M.cycle_rewrite_reasoning_level()
    return M.local_share.cycle_rewrite_reasoning_level()
end

function M.cycle_agents_reasoning_level()
    return M.local_share.cycle_agents_reasoning_level()
end

-- * notify stats *
function M.toggle_notify_stats()
    M.local_share.toggle_notify_stats()
end

function M.are_notify_stats_enabled()
    return M.local_share.are_notify_stats_enabled()
end

-- * rag *
function M.toggle_rag()
    M.local_share.toggle_rag()
    -- FOR NOW LSP won't be stopped/started on toggling RAG flag
    --  and actually, it may not ever make sense to stop it given if RAG is disabled then it won't be used for queries
    if M.is_rag_enabled() then
        print("restart nvim to ensure LSP is stopped")
    else
        print("restart nvim to ensure LSP is running")
    end
end

function M.is_rag_enabled()
    return M.local_share.is_rag_enabled()
end

return M
