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
--- @field get_chat_completions_url fun(): string
--- @field get_bearer_token fun(): string

--- @return Provider
function M.get_provider()
    if M.user_opts.provider == "copilot" then
        return require("ask-openai.providers.copilot")
    elseif M.user_opts.provider == "keychain" then
        return require("ask-openai.providers.keychain")
    else
        error("AskOpenAI: Invalid provider")
    end
end

return M
