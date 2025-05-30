--- ask-openai options
--- @class AskOpenAIOptions
--- @field model string
--- @field provider string
--- @field copilot CopilotOptions
--- @field verbose boolean
--- @field api_url string|nil
local default_options = {

    keymaps = {
        cmdline_ask = "<C-b>",
    },

    provider = "copilot",
    -- provider = "keyless",
    -- provider = function() ... end,

    --- @class CopilotOptions
    --- @field timeout number
    --- @field proxy string|nil
    --- @field insecure boolean
    copilot = {
        timeout = 30000,
        proxy = nil,
        insecure = false,
    },

    verbose = false, -- troubleshooting

    --- must be set to full endpoint URL, e.g. https://api.openai.com/v1/chat/completions
    api_url = nil,
    use_api_groq = false,
    use_api_openai = false,
    use_api_ollama = false, -- prefer this for local models unless not supported
    -- FYI rationale for use_* is to get completion without users needing to require a lookup or list of endpoints to complete

    -- request parameters:
    model = "gpt-4o",
    max_tokens = 200,
    -- PRN temperature
    -- in future, if add other ask helpers then I can move these into a nested table like copilot options

    tmp = {
        commandline = {
            -- TODO migrate here from top level (also consider other scenarios where I might want to configure different backend/mode/etc)
        },
        predictions = {
            -- TODO parse predicitons config (turn current config module into a function => do this later though when I get better idea of how to structure different scenarios)
            -- TODO likely are good reasons to consider multiple prediction scenarios too (not just one backend/model/etc)
            -- when it makes sense, configure diff model for predictions
            -- tmp == not a stable config architecture

            enabled = true,

            keymaps = {
                accept_all = "<Tab>",
                accept_line = "<C-right>",
                accept_word = "<M-right>",
                resume_stream = "<M-up>",
                pause_stream = "<M-down>",
            },

            provider = "keyless", -- TODO set to ? by default

            verbose = true,       -- TODO default to false

            api_url = nil,
            use_api_ollama = false,
            use_api_groq = false,
            use_api_openai = false,

            model = "qwen2.5-coder:3b-base-q8_0",
            max_tokens = 40,
        }
    }

}

local cached_options = default_options

---@param user_options AskOpenAIOptions
local function set_user_options(user_options)
    cached_options = vim.tbl_deep_extend("force", default_options, user_options or {})
end

---@return AskOpenAIOptions
local function get_options()
    return cached_options
end

--- @class Provider
--- @field get_bearer_token fun(): string
--- @field check fun() # optional
--- @field get_chat_completions_url fun(): string # optional

local function print_verbose(msg, ...)
    if not cached_options.verbose then
        return
    end
    print(msg, ...)
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

--- @type Provider
local cached_provider = nil

--- @return Provider
local function get_provider()
    if cached_provider == nil then
        cached_provider = _get_provider()
    end
    return cached_provider
end

local function get_chat_completions_url()
    local _provider = get_provider()
    if _provider.get_chat_completions_url then
        return _provider.get_chat_completions_url()
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

local function get_key_from_stdout(cmd_string)
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

local function get_validated_bearer_token()
    local bearer_token = get_provider().get_bearer_token()

    -- TODO can I reuse check() for these same checks? or just remove these and rely on checkhealth alone?
    -- VALIDATION => could push into provider, but especially w/ func provider it's good to do generic validation/tracing across all providers
    if bearer_token == nil then
        return 'Ask failed, bearer_token is nil'
    elseif bearer_token == "" then
        -- don't fail, just add to tracing
        print_verbose("FYI bearer_token is empty")
    end

    return bearer_token
end

local function check()
    local _provider = get_provider()
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
        if get_options().verbose then
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
        chat_url = get_chat_completions_url(),
        provider_type = get_options().provider,
        model = get_options().model,
    }
    vim.health.info(vim.inspect(options))
end
-- FYI one drawback of exports at end is that refactor rename requires two renames
-- FYI another drawback is F12 to nav is twice
-- FYI another drawback is order matters whereas with `function M.foo()` it doesn't matter
return {
    get_key_from_stdout = get_key_from_stdout,
    set_user_options = set_user_options,
    get_options = get_options,
    print_verbose = print_verbose,
    get_provider = get_provider,
    get_chat_completions_url = get_chat_completions_url,
    get_validated_bearer_token = get_validated_bearer_token,
    check = check
}
