local local_share = require("ask-openai.config.local_share")
local LlamaServerClient = require("ask-openai.backends.llama_cpp.llama_server_client")
local log = require("devtools.logs.logger"):universal()

local M = {}

--- @class ModelCacheEntry
--- @field name string|nil @Abbreviated model name (e.g. "qwen3")
--- @field model_info ModelInfo|nil @Full model info, or nil
--- @field ts integer

--- Track in-flight fetches to avoid duplicate background tasks.
--- key: base_url, value: true
local _fetch_in_progress = {}

-- cache: base_url -> ModelCacheEntry
local _model_cache = {}

local MODEL_PATTERNS = {
    -- FYI escape - => %- (easy to forget and will bork the pattern)
    --
    -- ALSO, order matters: more specific patterns first
    --
    -- ggml-org/Qwen3.6-35B-A3B-MTP-GGUF:Q8_0
    { pattern = "/Qwen3%.6.*%-MTP",  abbrev = "qwen3mtp" },
    -- ggml-org/Qwen3.6-35B-A3B-GGUF:Q8_0
    { pattern = "/Qwen3%.6",         abbrev = "qwen3" },
    -- g0t4/Qwen-AgentWorld-35B-A3B-GGUF:Q8_0
    { pattern = "/Qwen%-AgentWorld", abbrev = "agentworld" },
    -- ggml-org/gpt-oss-120b-GGUF
    { pattern = "/gpt%-oss",         abbrev = "gptoss" },
    -- google/gemma-4-26B-A4B-it-qat-q4_0-gguf
    { pattern = "/gemma%-4",         abbrev = "gemma4" },
}

--- Abbreviate a raw model name using pattern matching, or return the original name.
--- @param raw_model string|nil
--- @return string
local function abbreviate_model(raw_model)
    if not raw_model then
        return "MISSING_NAME"
    end

    for _, entry in ipairs(MODEL_PATTERNS) do
        if raw_model:match(entry.pattern) then
            return entry.abbrev
        end
    end

    return raw_model
end

local function NOOP() end

---@param base_url string
---@param callback ModelEntryCallback
local function refresh_model_info_cache_for(base_url, callback)
    callback = callback or NOOP

    local model_info = LlamaServerClient.get_model_info(base_url, { connect_timeout = 1, max_time = 3 })
    if not model_info then
        _fetch_in_progress[base_url] = nil
        callback({ name = "FETCH_FAILED" })
        return
    end

    local model_name = abbreviate_model(model_info.name)

    local entry = { name = model_name, model_info = model_info, base_url = base_url, ts = os.time() }
    _model_cache[base_url] = entry
    callback(entry) -- TODO or just return name?
end

---@alias ModelEntryCallback fun(entry: ModelCacheEntry)

--- Async model name lookup (cached is sync but requires callback pattern for now)
---@param base_url string The base URL of the llama-server (e.g. "http://paxy.lan:8012")
---@param callback ModelEntryCallback
function M.get_llama_server_model_info(base_url, callback)
    callback = callback or NOOP

    local function fetch()
        _fetch_in_progress[base_url] = true
        vim.schedule(function()
            refresh_model_info_cache_for(base_url, callback)
        end)
    end

    local cached = _model_cache[base_url]
    if cached then
        local cache_timeout_seconds = cached.name == nil and 1 or 120
        local expired = os.time() - cached.ts > cache_timeout_seconds
        if expired then
            -- trigger background refresh while using last value
            fetch()
        end
        callback(cached) -- respond with cached (albeit "expired") until refreshed
        return
    end

    if not _fetch_in_progress[base_url] then
        fetch()
    end

    callback({ name = "Pending..." })
end

---@class AskOpenAIOptions
local default_options = {
    commandline = {
        keymaps = {
            cmdline_ask = "<C-b>",
        },
        max_tokens = 10000, -- higher when using thinking models like 4K+ for gptoss120b (high 8K) and 10K for qwen3.6/agentworld
    },
    predictions = {
        keymaps = {
            accept_all = "<Tab>",
            accept_line = "<C-right>",
            accept_word = "<M-right>",
            new_prediction = "<M-Tab>",
        },
    }
}

local cached_options = default_options

---@return AskOpenAIOptions
function M.get_options()
    return cached_options
end

--- @class Endpoint
--- @field base_url string

--- @return table<string, Endpoint>
function M.get_endpoints()
    local gptoss_url = "http://ask.lan:8013"
    local qwen3_url = "http://ask.lan:8012"
    local gemma4_url = "http://ask.lan:8011"

    -- FYI fine by me to collapse Endpoint into a string
    -- I used to handle name here too but that became a hot mess due to async vs sync
    -- sync is needed for endpoint URL...
    -- async is fine for name (for all my use cases thus far
    return {
        cmdline = {
            base_url = gptoss_url,
        },
        qwen = {
            base_url = qwen3_url,
        },
        gptoss = {
            base_url = gptoss_url,
        },
        gemma4 = {
            base_url = gemma4_url,
        },
    }
end

---@param config_model_slug string   -- this is an abbreviated string used in the config file to store which model to use for a given situation, not the same as abbreviated model name NOR full model name from llama.cpp
function M.get_base_url(config_model_slug)
    local endpoints = M.get_endpoints()
    if endpoints[config_model_slug] then
        return endpoints[config_model_slug].base_url
    end
    return nil
end

function M.setup()
    local_share.setup()
    vim.schedule(function()
        -- schedule in background on startup
        M.get_endpoints()
    end)
end

M.local_share = local_share

return M
