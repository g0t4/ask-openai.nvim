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

    verbose = true,
    --- must be set to full endpoint URL, e.g. https://api.openai.com/v1/chat/completions
    api_url = nil,
    use_api_groq = false,
    use_api_openai = false,
    use_api_ollama = false, -- prefer this for local models unless not supported
    -- FYI rationale for use_* is to get completion without users needing to require a lookup or list of endpoints to complete

    model = "gpt-4o",
}

local options = default_options

---@param user_options AskOpenAIOptions
---@return AskOpenAIOptions
local function set_user_options(user_options)
    options = vim.tbl_deep_extend("force", default_options, user_options or {})
end

---@return AskOpenAIOptions
local function get_options()
    return options
end

--- @class Provider
--- @field get_chat_completions_url fun(): string -- TODO make get_default_completions_url?
--- @field get_bearer_token fun(): string

local function print_verbose(msg, ...)
    if not options.verbose then
        return
    end
    print(msg, ...)
end

--- @return Provider
local function _get_provider()
    if options.provider == "copilot" then
        print_verbose("AskOpenAI: Using Copilot")
        return require("ask-openai.providers.copilot")
    elseif options.provider == "keyless" then
        print_verbose("AskOpenAI: Using Keyless")
        return require("ask-openai.providers.keyless")
    elseif type(options.provider) == "function" then
        print_verbose("AskOpenAI: Using BYOK function")
        return require("ask-openai.providers.byok")(options.provider)
    else
        error("AskOpenAI: Invalid provider")
    end
end

--- @type Provider
local provider = nil

--- @return Provider
local function get_provider()
    if provider == nil then
        provider = _get_provider()
    end
    return provider
end

local function get_chat_completions_url()
    local _provider = get_provider()
    if _provider.get_chat_completions_url then
        return _provider.get_chat_completions_url()
    end

    if options.api_url then
        return options.api_url
    elseif options.use_api_groq then
        return "https://api.groq.com/openai/v1/chat/completions"
    elseif options.use_api_ollama then
        return "http://localhost:11434/api/chat"
    elseif options.use_api_openai then
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
}
