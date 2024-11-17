local M = {}

--- ask-openai options
--- @class AskOpenAIOptions
--- @field model string
--- @field provider string
local default_opts = {

    --- gpt-4o, gpt-4o-mini, etc
    model = "gpt-4o",

    --- TODO auto? (do this on first run, not on setup/startup)
    --- copilot, keychain
    -- provider = "keychain",
    provider = "copilot",
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


--- @return Provider
local function _get_provider()
    if M.user_opts.provider == "copilot" then
        return require("ask-openai.providers.copilot")
    elseif M.user_opts.provider == "keychain" then
        return require("ask-openai.providers.keychain")
    elseif M.user_opts.provider == "auto" then
        local copilot = require("ask-openai.providers.copilot")
        if copilot.is_auto_configured() then
            return copilot
        end
        local keychain = require("ask-openai.providers.keychain")
        if keychain.is_auto_configured() then
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
