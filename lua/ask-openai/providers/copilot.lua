-- FYI this all comes from other extensions:
-- https://github.com/yetone/avante.nvim/blob/main/lua/avante/providers/copilot.lua
--  => https://github.com/zbirenbaum/copilot.lua/blob/master/lua/copilot/auth.lua config file
--  => https://github.com/zed-industries/zed/blob/ad43bbbf5eda59eba65309735472e0be58b4f7dd/crates/copilot/src/copilot_chat.rs#L272 for authorization

local curl = require("plenary.curl")
local Path = require("plenary.path")

---FYI type annotations work nicely with coc (completions) and hover docs (Shift+K)
--- token from copilot_internal/v2/token
---@private
---@class AskOpenAICopilotInternalConfig
---@field annotations_enabled boolean
---@field chat_enabled boolean
---@field chat_jetbrains_enabled boolean
---@field code_quote_enabled boolean
---@field codesearch boolean
---@field copilotignore_enabled boolean
---@field endpoints {api: string, ["origin-tracker"]: string, proxy: string, telemetry: string}
---@field expires_at integer
---@field individual boolean
---@field nes_enabled boolean
---@field prompt_8k boolean
---@field public_suggestions string
---@field refresh_in integer
---@field sku string
---@field snippy_load_test_enabled boolean
---@field telemetry string
---@field token string
---@field tracking_id string
---@field vsc_electron_fetcher boolean
---@field xcode boolean
---@field xcode_chat boolean
local internal_config = nil

---@return "linux" | "darwin" | "windows"
local function get_os_name()
    local os_name = vim.uv.os_uname().sysname
    if os_name == "Linux" then
        return "linux"
    elseif os_name == "Darwin" then
        return "darwin"
    elseif os_name == "Windows_NT" then
        return "windows"
    else
        error("Unsupported operating system: " .. os_name)
    end
end

---@return string|nil, string|nil
local function get_oauth_token()
    local xdg_config = vim.fn.expand("$XDG_CONFIG_HOME")
    local os_name = get_os_name()
    ---@type string
    local config_dir

    if vim.tbl_contains({ "linux", "darwin" }, os_name) then
        config_dir = (xdg_config and vim.fn.isdirectory(xdg_config) > 0) and xdg_config or vim.fn.expand("~/.config")
    else
        config_dir = vim.fn.expand("~/AppData/Local")
    end

    -- actually copilot.vim uses both hosts.json and apps.json, whichever it finds first, in language-server.js (compiled/obfuscated, search for "hosts" and "apps" (include "" too) and you'll find the usage of either
    -- ALSO IIRC this is in language-server.js bundled with vscode github.copilot extension:
    --     GI="apps",fte="hosts",ute=class ute{constructor(t,r){this.ctx=t;this.persistenceManager=r}async getAuthRecord(t){if(t)return a
    --   THAT SAID, I haven't seen vscode extension host use that language-server.js, it seems to use dist/extension.js alone, so not sure why the other is even there! code --inspect-extensions and you'll see what it loads
    --- hosts.json (copilot.lua), apps.json (copilot.vim)
    ---@type Path[]
    local paths = vim.iter({ "hosts.json", "apps.json" }):fold({}, function(acc, path)
        local yason = Path:new(config_dir):joinpath("github-copilot", path)
        if yason:exists() then table.insert(acc, yason) end
        return acc
    end)
    if #paths == 0 then
        return nil, "You must setup copilot with either copilot.lua or copilot.vim first"
    end

    local yason = paths[1]

    ---@class OAuthToken
    ---@field user string
    ---@field oauth_token string

    return vim
        .iter(
        ---@type table<string, OAuthToken>
            vim.json.decode(yason:read())
        )
        :filter(function(k, _) return k:match("github.com") end)
        ---@param acc {oauth_token: string}
        :fold({}, function(acc, _, v)
            acc.oauth_token = v.oauth_token
            return acc
        end)
        .oauth_token
end

---@return AskOpenAICopilotInternalConfig|nil, string|nil
local function get_copilot_internal_config()
    -- no need to save to disk, vscode extension retrieves it repeatedly, so on startup is fine, it will expire soon enough anyways!
    -- until the token expires, it returns the same one when queried and as I said, vscode github.copilot extension frequently queries it

    if internal_config and internal_config.expires_at
        and math.floor(os.time()) < internal_config.expires_at then
        return internal_config
    end

    local oauth_token, error_message = get_oauth_token()
    if oauth_token == nil then
        return nil, error_message
    end

    local config = require("ask-openai.config")
    local response = curl.get(
        "https://api.github.com/copilot_internal/v2/token",
        {
            headers = {
                ["Authorization"] = "token " .. oauth_token,
                ["Accept"] = "application/json",
            },
            timeout = config.get_options().copilot.timeout,
            proxy = config.get_options().copilot.proxy,
            insecure = config.get_options().copilot.insecure,
        })

    if response.status == 200 then
        return vim.json.decode(response.body)
    end
    return nil, "Failed request copilot_internal/v2/token, response: " .. vim.inspect(response)
end

local function get_or_error_copilot_internal_config()
    local config, error_message = get_copilot_internal_config()
    if config == nil then
        error(error_message)
    end
    return config
end

---@return string
local function get_bearer_token()
    return get_or_error_copilot_internal_config().token
end

---@return string
local function get_chat_completions_url()
    -- FYI will be smth like: "api": "https://api.individual.githubcopilot.com"
    return get_or_error_copilot_internal_config().endpoints.api .. "/chat/completions"
end

local function check()
    -- test by renaming the ~/.config/github-copilot/hosts|apps.json file
    local config, _ = get_copilot_internal_config()
    if config == nil then
        vim.health.error("Copilot provider is missing copilot_internal/v2/token config")
        return
    end

    if require("ask-openai.config").get_options().verbose then
        -- if verbose then show copilot_internal/v2/token response
        local masked = vim.deepcopy(config)
        masked.token = "***" -- mask all of token
        -- PRN mask the tracking_id too?
        vim.health.info("copilot_internal/v2/token response: " .. vim.inspect(masked))
    end
end

--- @type Provider
return {
    get_chat_completions_url = get_chat_completions_url,
    get_bearer_token = get_bearer_token,
    check = check,
}
