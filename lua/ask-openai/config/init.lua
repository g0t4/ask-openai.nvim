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

--- Perform the actual fetch in the background.
--- @param base_url string
local function refresh_model_info_cache_for(base_url)
    local model_info = LlamaServerClient.get_model_info(base_url, { connect_timeout = 1, max_time = 3 })
    if not model_info then
        _fetch_in_progress[base_url] = nil
        return
    end

    local model_name = abbreviate_model(model_info.name)

    _model_cache[base_url] = { name = model_name, model_info = model_info, ts = os.time() }
    _fetch_in_progress[base_url] = nil
end

--- Query the llama-server for the first model's full information at the given base URL.
--- Non-blocking: returns cached value if available, otherwise kicks off a
--- background fetch and returns nil. Future calls will return the cached
--- value once the background fetch completes.
--- @param base_url string The base URL of the llama-server (e.g. "http://paxy.lan:8012")
--- @return ModelInfo? The cached model info, or nil if not yet cached.
function M.get_llama_server_model_info(base_url)
    -- 1. Check cache first
    local cached = _model_cache[base_url]
    if cached then
        local cache_timeout_seconds = cached.name == nil and 1 or 120
        if os.time() - cached.ts > cache_timeout_seconds then
            -- trigger background refresh while using last value
            vim.schedule(function()
                refresh_model_info_cache_for(base_url)
            end)
        end
        return cached.model_info
    end

    -- 2. Fetch already in progress — caller will retry later
    if _fetch_in_progress[base_url] then
        return nil
    end

    -- 3. Start a new background fetch
    _fetch_in_progress[base_url] = true
    vim.schedule(function()
        refresh_model_info_cache_for(base_url)
    end)

    return nil
end

--- Query the llama-server for the first model's abbreviated name at the given base URL.
--- Non-blocking: returns cached value if available, otherwise kicks off a
--- background fetch and returns nil. Future calls will return the cached
--- value once the background fetch completes.
--- @param base_url string The base URL of the llama-server (e.g. "http://paxy.lan:8012")
--- @return string|nil The cached abbreviated model name, or nil if not yet cached.
function M.get_llama_server_model_name(base_url)
    -- 1. Check cache first
    local cached = _model_cache[base_url]
    if cached then
        local cache_timeout_seconds = cached.name == nil and 1 or 120
        if os.time() - cached.ts > cache_timeout_seconds then
            -- trigger background refresh while using last value
            vim.schedule(function()
                refresh_model_info_cache_for(base_url)
            end)
        end
        return cached.name
    end

    -- 2. Fetch already in progress — assume caller will retry later
    if _fetch_in_progress[base_url] then
        return "Pending..."
    end

    -- 3. Start a new background fetch
    _fetch_in_progress[base_url] = true
    vim.schedule(function()
        refresh_model_info_cache_for(base_url)
    end)

    return "Pending..."
end

---@class Provider
---@field get_bearer_token fun(): string
---@field check fun() # optional
---@field get_cmdline_base_url fun(): string # optional

--- ask-openai options
---@class AskOpenAIOptions
---@field model string
---@field provider string
---@field copilot CopilotOptions
---@field api_url string|nil
local default_options = {

    keymaps = {
        cmdline_ask = "<C-b>",
    },

    provider = "copilot",
    -- provider = "keyless",
    -- provider = function() ... end,

    ---@class CopilotOptions
    ---@field timeout number
    ---@field proxy string|nil
    ---@field insecure boolean
    copilot = {
        timeout = 30000,
        proxy = nil,
        insecure = false,
    },

    --- must be set to full endpoint URL, e.g. https://api.openai.com/v1/chat/completions
    api_url = nil,
    use_api_groq = false,
    use_api_openai = false,
    use_api_ollama = false, -- prefer this for local models unless not supported
    -- FYI rationale for use_* is to get completion without users needing to require a lookup or list of endpoints to complete

    -- request parameters:
    model = "gpt-4o",
    max_tokens = 10000, -- higher when using thinking models like 4K+ for gptoss120b (high 8K) and 10K for qwen3.6/agentworld
    -- PRN temperature
    -- in future, if add other ask helpers then I can move these into a nested table like copilot options

    tmp = {
        commandline = {
            -- TODO migrate here from top level (also consider other scenarios where I might want to configure different backend/mode/etc)
        },
        predictions = {
            keymaps = {
                accept_all = "<Tab>",
                accept_line = "<C-right>",
                accept_word = "<M-right>",
                resume_stream = "<M-up>",
                pause_stream = "<M-down>",
                new_prediction = "<M-Tab>",
            },
        }
    }

}

local cached_options = default_options

---@param user_options AskOpenAIOptions
local function set_user_options(user_options)
    cached_options = vim.tbl_deep_extend("force", default_options, user_options or {})
end

---@return AskOpenAIOptions
function M.get_options()
    return cached_options
end

--- @class Endpoint
--- @field name string
--- @field base_url string

--- @return table<string, Endpoint>
function M.get_endpoints()
    local gptoss_url = "http://ask.lan:8013"
    local qwen3_url = "http://ask.lan:8012"
    local gemma4_url = "http://ask.lan:8011"

    local gptoss_model = M.get_llama_server_model_name(gptoss_url)
    local qwen3_model = M.get_llama_server_model_name(qwen3_url)
    local gemma4_model = M.get_llama_server_model_name(gemma4_url)

    return {
        cmdline = {
            name = nil,
            base_url = M.get_cmdline_base_url(),
        },
        qwen = {
            name = qwen3_model,
            base_url = qwen3_url,
        },
        gptoss = {
            name = gptoss_model,
            base_url = gptoss_url,
        },
        gemma4 = {
            name = gemma4_model,
            base_url = gemma4_url,
        },
    }
end

function M.get_base_url(model)
    local endpoints = M.get_endpoints()
    if endpoints[model] then
        return endpoints[model].base_url
    end
    return nil
end

local function _get_provider()
    -- FYI prints below only show on first run b/c provider is cached by get_provider() so NBD to add that extra info which is useful to know config is correct w/o toggling verbose on and getting a wall of logs
    if cached_options.provider == "copilot" then
        print("AskOpenAI: Using Copilot")
        return require("ask-openai.providers.copilot")
    elseif cached_options.provider == "keyless" then
        print("AskOpenAI: Using Keyless")
        return require("ask-openai.providers.keyless")
    elseif type(cached_options.provider) == "function" then
        print("AskOpenAI: Using BYOK function")
        return require("ask-openai.providers.byok")(cached_options.provider)
    else
        error("AskOpenAI: Invalid provider")
    end
end

---@type Provider
local cached_provider = nil

---@return Provider
function M.get_provider()
    if cached_provider == nil then
        cached_provider = _get_provider()
    end
    return cached_provider
end

function M.get_cmdline_base_url()
    local _provider = M.get_provider()
    if _provider.get_cmdline_base_url then
        return _provider.get_cmdline_base_url()
    end

    if cached_options.api_url then
        return cached_options.api_url
    elseif cached_options.use_api_groq then
        return "https://api.groq.com/openai/v1/chat/completions"
    elseif cached_options.use_api_ollama then
        return "http://localhost:11434/v1/chat/completions"
    elseif cached_options.use_api_openai then
        return "https://api.openai.com/v1/chat/completions"
    else
        -- default to openai
        return "https://api.openai.com/v1/chat/completions"
    end
end

function M.get_key_from_stdout(cmd_string)
    local handle = io.popen(cmd_string)
    if not handle then
        return nil
    end

    -- remove any extra whitespace
    local api_key = handle:read("*a"):gsub("%s+", "")

    handle:close()

    -- ok if empty/nil, will be checked
    return api_key
end

function M.get_validated_bearer_token()
    local bearer_token = M.get_provider().get_bearer_token()

    -- TODO can I reuse check() for these same checks? or just remove these and rely on checkhealth alone?
    -- VALIDATION => could push into provider, but especially w/ func provider it's good to do generic validation/tracing across all providers
    if bearer_token == nil then
        return 'Ask failed, bearer_token is nil'
    elseif bearer_token == "" then
        -- don't fail, just add to tracing
        log:info("FYI bearer_token is empty")
    end

    return bearer_token
end

function M.check()
    local _provider = M.get_provider()
    if _provider.check then
        _provider.check()
    end

    local bearer_token = _provider.get_bearer_token()
    if bearer_token == nil then
        vim.health.error("bearer_token is nil")
    elseif bearer_token == "" then
        vim.health.error("bearer_token is empty")
    else
        vim.health.ok("bearer_token retrieved")
        if local_share.is_trace_logging_enabled() then
            -- TODO extract mask function and test it, try to submit to plenary? or does plenary have one?
            local len = string.len(bearer_token)
            local num = math.min(5, math.floor(len * 0.07)) -- first and last 7%, max of 5 chars
            if num < 1 then
                vim.health.info("bearer_token too short to show start/end")
            else
                local masked = string.sub(bearer_token, 1, num)
                    .. "*****"
                    .. string.sub(bearer_token, -num)
                vim.health.info("bearer_token: " .. masked)
            end
        end
    end

    local options = {
        chat_url = M.get_cmdline_base_url(),
        provider_type = M.get_options().provider,
        model = M.get_options().model,
    }
    vim.health.info(vim.inspect(options))
end

function M.setup(user_options)
    set_user_options(user_options)
    local_share.setup()
end

M.local_share = local_share

return M
