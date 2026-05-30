local local_share = require("ask-openai.config.local_share")
local LlamaServerClient = require("ask-openai.backends.llama_cpp.llama_server_client")

local M = {}

-- cache for model names per base url (host:port)
-- stores { value = string|nil, ts = integer }
local _model_cache = {}

--- Query the llama-server for the model name running at the given base URL.
--- Uses the `/v1/models` endpoint and caches the result per URL.
--- @param base_url string The base URL of the llama-server (e.g. "http://paxy.lan:8012")
--- @return string|nil The model abbreviation, or nil if server request failed. Returns "OFFLINE" for unknown models.
function M.get_llama_server_model(base_url)
    -- TODO figure out why ltn12 and socket.http packages together are not working on wesdemos, but working fine on wes user... WTF
    --   my innermost JSON lua module is just returning NOTHING on all requests as wesdemos... FUUUUU
    --   might have smth to do with neovim v0.12 install (then remove) and lua5.1 missing now (kinda)... though luarocks on both users has the packages I need... I have no damn idea anymore

    local cached = _model_cache[base_url]
    if cached then
        local timeout = cached.value == nil and 1 or 10
        if os.time() - cached.ts < timeout then
            return cached.value
        end
    end

    local response = LlamaServerClient.get_models(base_url, { connect_timeout = 1, max_time = 3 })  -- 1s connect + 3s max-time to fail fast on offline server
    if not response or response.code ~= 200 then
        return nil
    end

    local body = response.body
    local model_name = nil
    if type(body) == "table" then
        if body.models and #body.models > 0 then
            local first_model = body.models[1]
            if type(first_model) == "table" and first_model.name then
                model_name = first_model.name
            end
        else
            model_name = "no model.id"
        end
    end

    -- Model name abbreviation lookup table
    local model_name_map = {
        ["ggml-org/Qwen3.6-35B-A3B-MTP-GGUF:Q8_0"] = "qwen3.6mtp",
        ["ggml-org/Qwen3.6-35B-A3B-GGUF:Q8_0"] = "qwen3",
        ["ggml-org/gpt-oss-120b-GGUF"] = "gptoss",
    }

    -- Apply abbreviation from lookup table, or fall back to "OFFLINE" sentinel
    model_name = model_name_map[model_name] or "OFFLINE"

    _model_cache[base_url] = { value = model_name, ts = os.time() }
    return model_name
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
    max_tokens = 2000, -- higher when using thinking models like gptoss120b
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

function M.print_verbose(msg, ...)
    if local_share.is_trace_logging_enabled() then
        print(msg, ...)
    end
end

--- @class Endpoint
--- @field name string
--- @field base_url string

--- @return table<string, Endpoint>
function M.get_endpoints()
    local gptoss_url = "http://ask.lan:8013"
    local qwen3_url = "http://ask.lan:8012"

    local gptoss_model = M.get_llama_server_model(gptoss_url)
    local qwen3_model = M.get_llama_server_model(qwen3_url)

    local endpoints = {
        agents = {
            name = qwen3_model or "OFFLINE",
            base_url = qwen3_url,
        },
        rewrite = {
            name = gptoss_model or "OFFLINE",
            base_url = gptoss_url,
        },
        cmdline = {
            name = nil,
            base_url = M.get_cmdline_base_url(),
        },
        gptoss = {
            name = gptoss_model or "OFFLINE",
            base_url = gptoss_url,
        },
        summarizer = {
            name = gptoss_model or "OFFLINE",
            base_url = gptoss_url,
        },
        qwen3 = {
            name = qwen3_model or "OFFLINE",
            base_url = qwen3_url,
        },
    }
    return endpoints
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
        M.print_verbose("FYI bearer_token is empty")
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
