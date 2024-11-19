--- ask-openai options
--- @class AskOpenAIOptions
--- @field model string
--- @field provider string
--- @field copilot CopilotOptions
--- @field keychain KeychainOptions
local default_options = {

    keymaps = {
        cmdline_ask = "<C-b>",
    },
    --- gpt-4o, gpt-4o-mini, etc
    model = "gpt-4o",
    -- model = "llama3.2-vision:11b",
    -- FYI curl localhost:11434/v1/models (ollama)

    --- copilot, keychain
    -- provider = "auto",
    -- provider = "keychain",
    provider = "copilot",
    -- provider = "keyless",

    --- @class CopilotOptions
    --- @field timeout number
    --- @field proxy string|nil
    --- @field insecure boolean
    copilot = {
        timeout = 30000,
        proxy = nil,
        insecure = false,
    },

    --- @class KeychainOptions
    --- @field service string - service name
    --- @field account string - account name
    keychain = {
        service = "openai",
        account = "ask",
    },

    verbose = true,
    api_url = nil, -- leave nil for defaults (does not apply to copilot provider)
    -- FYI look at :messages after first ask to make sure it's using expected provider
}

local options = default_options

---@param options AskOpenAIOptions
---@return AskOpenAIOptions
local function set_user_options(user_options)
    options = vim.tbl_deep_extend("force", default_options, user_options or {})
end

---@return AskOpenAIOptions
local function get_options()
    return options
end

--- @class Provider
--- @field is_auto_configured fun(): boolean
--- @field get_chat_completions_url fun(): string
--- @field get_bearer_token fun(): string

local function print_verbose(msg)
    if not options.verbose then
        return
    end
    print(msg)
end

--- @return Provider
local function _get_provider()
    if options.provider == "copilot" then
        print_verbose("AskOpenAI: Using Copilot")
        return require("ask-openai.providers.copilot")
    elseif options.provider == "keychain" then
        print_verbose("AskOpenAI: Using Keychain")
        return require("ask-openai.providers.keychain")
    elseif options.provider == "keyless" then
        print_verbose("AskOpenAI: Using Keyless")
        return require("ask-openai.providers.keyless")
    elseif options.provider == "auto" then
        local copilot = require("ask-openai.providers.copilot")
        if copilot.is_auto_configured() then
            -- FYI I like showing this on first ask, it shows in cmdline until response (cmdline) and only first time, it helps people confirm which is used too!
            print_verbose("AskOpenAI: Auto Using Copilot")
            return copilot
        end
        local keychain = require("ask-openai.providers.keychain")
        if keychain.is_auto_configured() then
            print_verbose("AskOpenAI: Auto Using Keychain")
            return keychain
        end
        error("AskOpenAI: No auto provider available")
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

return {
    set_user_options = set_user_options,
    get_options = get_options,
    print_verbose = print_verbose,
    get_provider = get_provider,
}
