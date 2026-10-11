local HLGroups = require("ask-openai.hlgroups")

--- Insert thousands separators into an integer for display (e.g. 12345 -> "12,345").
---@param n integer
---@return string
local function comma_separate(n)
    local s = tostring(n)
    local result = ""
    local count = 0
    for i = #s, 1, -1 do
        count = count + 1
        result = s:sub(i, i) .. result
        if count % 3 == 0 and i > 1 then
            result = "," .. result
        end
    end
    return result
end

--- A tiny borderless float that overlays the top-right corner of a parent window
--- and stays pinned there regardless of scrolling (unlike an extmark, which is
--- always anchored to a buffer line). Used to show a live token count.
---@class TokenBadge
---@field anchor_win_id integer
---@field win_id? integer
---@field buf integer
local TokenBadge = {}
TokenBadge.__index = TokenBadge

---@param anchor_win_id integer -- the window the badge is pinned to (top-right)
---@return TokenBadge
function TokenBadge:new(anchor_win_id)
    local self = setmetatable({}, { __index = TokenBadge })
    self.anchor_win_id = anchor_win_id
    self.win_id = nil
    self.buf = vim.api.nvim_create_buf(false, true)
    return self
end

--- Show (or reposition) the badge with the given text.
---@param text string
function TokenBadge:show(text)
    if not self.anchor_win_id or not vim.api.nvim_win_is_valid(self.anchor_win_id) then
        return
    end

    local text_width = vim.str_utfindex(text)
    local anchor_width = vim.api.nvim_win_get_width(self.anchor_win_id)
    local col = math.max(0, anchor_width - text_width - 1)

    vim.bo[self.buf].modifiable = true
    vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, { text })
    vim.bo[self.buf].modifiable = false

    local config = {
        relative = "win",
        win = self.anchor_win_id,
        row = 0,
        col = col,
        width = text_width,
        height = 1,
        style = "minimal",
        focusable = false,
        zindex = 100,
        noautocmd = true,
    }

    if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
        vim.api.nvim_win_set_config(self.win_id, config)
    else
        self.win_id = vim.api.nvim_open_win(self.buf, false, config)
    end

    vim.api.nvim_set_option_value("winhighlight", "NormalFloat:" .. HLGroups.TOKEN_BADGE, { win = self.win_id })
end

--- Show the token count in the top-right corner.
---@param total_tokens integer
function TokenBadge:show_token_count(total_tokens)
    self:show("tokens: " .. comma_separate(total_tokens))
end

--- Close the badge window (if open).
function TokenBadge:hide()
    if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
        vim.api.nvim_win_close(self.win_id, false)
    end
    self.win_id = nil
end

return TokenBadge
