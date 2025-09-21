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

local function load_config()
    local default = {
        predictions = { enabled = true },
        verbose_logs = false,
        rag = { enabled = true },
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

-- * verbose logs *
function M.are_verbose_logs_enabled()
    return get().verbose_logs
end

function M.toggle_verbose_logs()
    local cfg = get()
    cfg.verbose_logs = not cfg.verbose_logs
    save()
    return cfg.verbose_logs
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

function M.setup()
end

return M
