local M = {}

local config = nil

local config_path = vim.fn.stdpath('data') .. '/ask-openai/config.json'

local function file_exists(path)
    local file = io.open(path, 'r')
    if file then
        file:close()
        return true
    end
    return false
end

local function mkdir_p(path)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
end

-- * model constants
M.GPTOSS = "gptoss"
M.QWEN = "qwen"
M.GLM = "glm"
M.GEMMA4 = "gemma4"
M.DEFAULT_MODEL = M.GPTOSS

local function load_config()
    local default = {
        predictions = { enabled = true },
        notify_stats = false,
        rag = { enabled = true },

        -- model agnostic params
        fim = { semantic_grep = { all_files = false } },

        -- model specific params
        [M.GPTOSS] = {}, -- allow downstream to define defaults
        [M.QWEN] = {},
        [M.GLM] = {},
        [M.GEMMA4] = {},
    }

    if file_exists(config_path) then
        local content = io.open(config_path, 'r'):read('*a')
        -- require here to avoid loop:
        local safely = require('ask-openai.helpers.safely')
        local ok, parsed_config = safely.decode_json(content)
        if ok and type(parsed_config) == 'table' then
            return vim.tbl_deep_extend('force', default, parsed_config)
        end
    else
        mkdir_p(config_path)
    end

    return default
end

local function save_config(data)
    local file = io.open(config_path, 'w')
    if file then
        file:write(vim.json.encode(data))
        file:close()
    end
end

local function get()
    if not config then
        config = load_config()
    end
    return config
end

local function save()
    if config then
        save_config(config)
    end
end


-- * predictions *
function M.set_predictions_enabled()
    local cfg = get()
    cfg.predictions.enabled = true
    save()
end

function M.set_predictions_disabled()
    local cfg = get()
    cfg.predictions.enabled = false
    save()
end

function M.are_predictions_enabled()
    return get().predictions.enabled
end

function M.toggle_predictions()
    local cfg = get()
    cfg.predictions.enabled = not cfg.predictions.enabled
    save()
    return cfg.predictions.enabled
end

-- * notify stats *
function M.are_notify_stats_enabled()
    return get().notify_stats
end

function M.toggle_notify_stats()
    local cfg = get()
    cfg.notify_stats = not cfg.notify_stats
    save()
    return cfg.notify_stats
end

-- * rag *
function M.is_rag_enabled()
    return get().rag.enabled
end

function M.toggle_rag()
    local cfg = get()
    cfg.rag.enabled = not cfg.rag.enabled
    save()
    return cfg.rag.enabled
end

-- * agents model
function M.get_agents_model()
    local cfg = get()
    return cfg.agents and cfg.agents.model or M.DEFAULT_MODEL
end

function M.set_agents_model(model)
    local cfg = get()
    cfg.agents = cfg.agents or {}
    cfg.agents.model = model
    save()
end

local _model_cycle = { M.GPTOSS, M.QWEN, M.GEMMA4, M.GLM }
local function _next_model(current)
    for i, m in ipairs(_model_cycle) do
        if m == current then
            return _model_cycle[i % #_model_cycle + 1]
        end
    end
    return _model_cycle[1]
end

function M.toggle_agents_model()
    local next_model = _next_model(M.get_agents_model())
    M.set_agents_model(next_model)
    return next_model
end

-- * rewrite model
function M.get_rewrite_model()
    local cfg = get()
    return cfg.rewrite and cfg.rewrite.model or M.DEFAULT_MODEL
end

function M.set_rewrite_model(model)
    local cfg = get()
    cfg.rewrite = cfg.rewrite or {}
    cfg.rewrite.model = model
    save()
end

function M.toggle_rewrite_model()
    local next_model = _next_model(M.get_rewrite_model())
    M.set_rewrite_model(next_model)
    return next_model
end

-- * FIM model
function M.get_fim_model()
    local cfg = get()
    return cfg.fim and cfg.fim.model or M.DEFAULT_MODEL
end

function M.set_fim_model(model)
    local cfg = get()
    cfg.fim = cfg.fim or {}
    cfg.fim.model = model
    save()
end

function M.toggle_fim_model()
    local next_model = _next_model(M.get_fim_model())
    M.set_fim_model(next_model)
    return next_model
end

-- * FIM semantic_grep's file type(s)
function M.get_fim_semantic_grep_all_files()
    -- TODO IF I KEEP THIS, I have to add it to settings b/c I wanna see when it is on/off (could affect regular FIM's semantic_grep which in many cases doesn't need cross language matches)
    local cfg = get()
    return cfg.fim
        and cfg.fim.semantic_grep
        and cfg.fim.semantic_grep.all_files
        or false
end

function M.toggle_fim_semantic_grep_all_files()
    local cfg = get()
    cfg.fim = cfg.fim or {}
    cfg.fim.semantic_grep = cfg.fim.semantic_grep or {}
    cfg.fim.semantic_grep.all_files = not (cfg.fim.semantic_grep.all_files or false)
    save()
    return cfg.fim.semantic_grep.all_files
end

-- * gptoss FIM reasoning level
-- thinking model's reasoning level (for thinking models, including FIM)
function M.set_fim_reasoning_level(level)
    local cfg = get()
    local model = M.get_fim_model()
    cfg[model] = cfg[model] or {}
    cfg[model].fim_reasoning_level = level
    save()
end

---@enum GptOssReasoningLevel
M.GptOssReasoningLevel = {
    off = "off",
    low = "low",
    medium = "medium",
    high = "high"
}

M.THINKING_OFF = "off"
M.THINKING_ON = "on"

---@return string GptOssReasoningLevel
function M.get_fim_reasoning_level()
    local cfg = get()
    local model = M.get_fim_model()
    cfg[model] = cfg[model] or {}
    return cfg[model].fim_reasoning_level or M.THINKING_OFF -- off can be default since that is universal in my experience (chat template prefill forces no thinking)
end

local function _cycle_reasoning_level(current, model)
    if model == M.GPTOSS then
        if current == M.GptOssReasoningLevel.off then
            return M.GptOssReasoningLevel.low
        elseif current == M.GptOssReasoningLevel.low then
            return M.GptOssReasoningLevel.medium
        elseif current == M.GptOssReasoningLevel.medium then
            return M.GptOssReasoningLevel.high
        else
            return M.GptOssReasoningLevel.off
        end
    else
        return current == M.THINKING_OFF and M.THINKING_ON or M.THINKING_OFF
    end
end

function M.cycle_fim_reasoning_level()
    local current = M.get_fim_reasoning_level()
    local model = M.get_fim_model()
    local next_level = _cycle_reasoning_level(current, model)
    M.set_fim_reasoning_level(next_level)
    return next_level
end

-- * AgentsFrontend reasoning level
function M.set_agents_reasoning_level(level)
    -- FYI I routinely use different levels per frontend
    local cfg = get()
    local model = M.get_agents_model()
    -- TODO! check name is stored normalized (same as expected for settings)
    cfg[model] = cfg[model] or {}
    cfg[model].agents_reasoning_level = level
    save()
end

function M.get_agents_reasoning_level()
    local cfg = get()
    local model = M.get_agents_model()
    -- TODO! check name is stored normalized (same as expected for settings)
    cfg[model] = cfg[model] or {}
    return cfg[model].agents_reasoning_level or M.THINKING_OFF
end

function M.cycle_agents_reasoning_level()
    local current = M.get_agents_reasoning_level()
    local model = M.get_agents_model()
    local next_level = _cycle_reasoning_level(current, model)
    M.set_agents_reasoning_level(next_level)
    return next_level
end

-- * RewriteFrontend reasoning level
function M.set_rewrite_reasoning_level(level)
    local cfg = get()
    local model = M.get_rewrite_model()
    cfg[model] = cfg[model] or {}
    cfg[model].rewrite_reasoning_level = level or M.THINKING_OFF
    save()
end

function M.get_rewrite_reasoning_level()
    local cfg = get()
    local model = M.get_rewrite_model()
    cfg[model] = cfg[model] or {}
    return cfg[model].rewrite_reasoning_level or M.GptOssReasoningLevel.low
end

function M.cycle_rewrite_reasoning_level()
    local current = M.get_rewrite_reasoning_level()
    local model = M.get_rewrite_model()
    local next_level = _cycle_reasoning_level(current, model)
    M.set_rewrite_reasoning_level(next_level)
    return next_level
end

function M.setup()
end

return M
