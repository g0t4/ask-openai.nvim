local M = {}

--- ask-openai options
--- @class AskOpenAIOptions
--- @field model string
--- @field provider string
--- @field copilot CopilotOptions
local default_opts = {

    --- gpt-4o, gpt-4o-mini, etc
    model = "gpt-4o",

    --- TODO auto? (do this on first run, not on setup/startup)
    --- copilot, keychain
    -- provider = "keychain",
    -- provider = "copilot",
    provider = "auto",

    --- @class CopilotOptions
    --- @field timeout number
    --- @field proxy string|nil
    --- @field insecure boolean
    copilot = {
        timeout = 30000,
        proxy = nil,
        insecure = false,
    },

    keychain = {
        service = "openai",
        account = "ask",
    },

    verbose = true,

    -- FYI look at :messages after first ask to make sure it's using expected provider
}

function M.set_user_opts(opts)
    --- FYI lua didn't need @type here to infer the type from above... but adding it to be clear, I would define this here except that I have defaults above and I can add descriptions to the fields too, inline (ie models/providers)
    --- @type AskOpenAIOptions
    M.user_opts = vim.tbl_deep_extend("force", default_opts, opts or {})
end

--- @class Provider
--- @field is_auto_configured fun(): boolean
--- @field get_chat_completions_url fun(): string
--- @field get_bearer_token fun(): string

function M.print_verbose(msg)
    if not M.user_opts.verbose then
        return
    end
    print(msg)
end

--- @return Provider
local function _get_provider()
    if M.user_opts.provider == "copilot" then
        M.print_verbose("AskOpenAI: Using Copilot")
        return require("ask-openai.providers.copilot")
    elseif M.user_opts.provider == "keychain" then
        M.print_verbose("AskOpenAI: Using Keychain")
        return require("ask-openai.providers.keychain")
    elseif M.user_opts.provider == "auto" then
        local copilot = require("ask-openai.providers.copilot")
        if copilot.is_auto_configured() then
            -- FYI I like showing this on first ask, it shows in cmdline until response (cmdline) and only first time, it helps people confirm which is used too!
            M.print_verbose("AskOpenAI: Auto Using Copilot")
            return copilot
        end
        local keychain = require("ask-openai.providers.keychain")
        if keychain.is_auto_configured() then
            M.print_verbose("AskOpenAI: Auto Using Keychain")
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
function M.get_provider()
    if provider == nil then
        provider = _get_provider()
    end
    return provider
end

return M
