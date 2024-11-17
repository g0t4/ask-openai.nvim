-- FYI this all comes from other extensions:
-- https://github.com/yetone/avante.nvim/blob/main/lua/avante/providers/copilot.lua
--  => https://github.com/zbirenbaum/copilot.lua/blob/master/lua/copilot/auth.lua config file
--  => https://github.com/zed-industries/zed/blob/ad43bbbf5eda59eba65309735472e0be58b4f7dd/crates/copilot/src/copilot_chat.rs#L272 for authorization

-- TODO How do I specify plenary as a dep?
local curl = require("plenary.curl")
local Path = require("plenary.path")

local M = {}

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

---@class OAuthToken
---@field user string
---@field oauth_token string
---
---@return string
M.get_oauth_token = function()
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
    if #paths == 0 then error("You must setup copilot with either copilot.lua or copilot.vim", 2) end

    local yason = paths[1]
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

---@param str string
---@param opts? {suffix?: string, prefix?: string}
local function trim(str, opts)
  if not opts then return str end
  local res = str
  if opts.suffix then
    res = str:sub(#str - #opts.suffix + 1) == opts.suffix and str:sub(1, #str - #opts.suffix) or str
  end
  if opts.prefix then res = str:sub(1, #opts.prefix) == opts.prefix and str:sub(#opts.prefix + 1) or str end
  return res
end

M.chat_auth_url = "https://api.github.com/copilot_internal/v2/token"
M.chat_completion_url = function(base_url) return trim(base_url, { prefix = "/" }) .. "/chat/completions" end


return M