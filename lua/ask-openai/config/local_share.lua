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


-- * log level constants
local LEVEL_NUMBERS = {
    TRACE = 0,
    INFO = 1,
    WARN = 2,
    ERROR = 3,
}
M.LOG_LEVEL_NUMBERS = LEVEL_NUMBERS
local LEVEL_TEXT_TO_NUMBER = {
    ["TRACE"] = LEVEL_NUMBERS.TRACE,
    ["INFO"]  = LEVEL_NUMBERS.INFO,
    ["WARN"]  = LEVEL_NUMBERS.WARN,
    ["ERROR"] = LEVEL_NUMBERS.ERROR,
}
M.LOG_LEVEL_TEXT_TO_NUMBER = LEVEL_TEXT_TO_NUMBER
local LEVEL_NUMBER_TO_TEXT = {
    [LEVEL_NUMBERS.TRACE] = "TRACE",
    [LEVEL_NUMBERS.INFO]  = "INFO",
    [LEVEL_NUMBERS.WARN]  = "WARN",
    [LEVEL_NUMBERS.ERROR] = "ERROR",
}
M.LOG_LEVEL_NUMBER_TO_TEXT = LEVEL_NUMBER_TO_TEXT
local DEFAULT_LOG_LEVEL_NUMBER = LEVEL_NUMBERS.WARN

local function load_config()
    local default = {
        predictions = { enabled = true },
        notify_stats = false,
        rag = { enabled = true },
        log_threshold_text = LEVEL_NUMBER_TO_TEXT[DEFAULT_LOG_LEVEL_NUMBER],
    }

    if file_exists(config_path) then
        local content = io.open(config_path, 'r'):read('*a')
        local ok, parsed_config = pcall(vim.json.decode, content)
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

-- * log threshold *
local MAX_LOG_THRESHOLD = 2 -- must always show WARN/ERROR

---@return string, number
function M.cycle_log_verbosity()
    local current_text, current_number = M.get_log_threshold()
    local next_number = (current_number + 1) % (MAX_LOG_THRESHOLD + 1)
    local cfg = get()
    cfg.log_threshold_text = LEVEL_NUMBER_TO_TEXT[next_number]
    save()
    return cfg.log_threshold_text, next_number
end

---@return string level_text, number level_number
function M.get_log_threshold()
    local cfg = get()
    local text = cfg.log_threshold_text or LEVEL_NUMBER_TO_TEXT[DEFAULT_LOG_LEVEL_NUMBER]
    local number = LEVEL_TEXT_TO_NUMBER[text]
    return text, number
end

--- @return boolean
function M.is_trace_logging_enabled()
    return M.get_log_threshold() < 1
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

-- * FIM model

function M.get_fim_model()
    local cfg = get()
    local model = cfg.fim and cfg.fim.model or nil
    -- enforce choices on read
    if model == "gptoss" then
        return model
    else
        return "qwen25coder"
    end
end

function M.set_fim_model(model)
    local cfg = get()
    cfg.fim = cfg.fim or {}
    cfg.fim.model = model
    save()
end

function M.toggle_fim_model()
    local current = M.get_fim_model()
    local next_model = (current == "gptoss") and "qwen25coder" or "gptoss"
    M.set_fim_model(next_model)
    return next_model
end

function M.setup()
end

return M
