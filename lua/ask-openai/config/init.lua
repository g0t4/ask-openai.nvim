local local_share = require("ask-openai.config.local_share")

--- @class Provider
--- @field get_bearer_token fun(): string
--- @field check fun() # optional
--- @field get_chat_completions_url fun(): string # optional
local M = {}

--- ask-openai options
--- @class AskOpenAIOptions
--- @field model string
--- @field provider string
--- @field copilot CopilotOptions
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

            keymaps = {
                accept_all = "<Tab>",
                accept_line = "<C-right>",
                accept_word = "<M-right>",
                resume_stream = "<M-up>",
                pause_stream = "<M-down>",
                new_prediction = "<M-Tab>",
            },

            provider = "keyless", -- TODO set to ? by default

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
function M.get_options()
    return cached_options
end

function M.print_verbose(msg, ...)
    -- ?? move this to logger, or?
    if not local_share.are_verbose_logs_enabled() then
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
function M.get_provider()
    if cached_provider == nil then
        cached_provider = _get_provider()
    end
    return cached_provider
end

function M.get_chat_completions_url()
    local _provider = M.get_provider()
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
        if local_share.are_verbose_logs_enabled() then
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
        chat_url = M.get_chat_completions_url(),
        provider_type = M.get_options().provider,
        model = M.get_options().model,
    }
    vim.health.info(vim.inspect(options))
end

function M.setup(user_options)
    set_user_options(user_options)
    local_share.setup()
end

function M.lualine()
    -- FYI this is an example, copy and modify it to your liking!
    -- reference: "󰼇" "󰼈"
    --  ''            󰨰
    return {
        function()
            local icons = '󰼇'
            if local_share.are_verbose_logs_enabled() then
                icons = icons .. '  '
            end
            return icons
        end,
        color = function()
            local fg_color = ''
            if not local_share.are_predictions_enabled() then
                fg_color = '#333333'
            end
            return { fg = fg_color }
        end,
    }
end

M.local_share = local_share

return M
