--- Paste-mode logic for voiced: arm at the cursor, then the next final
--- transcription is inserted into the captured buffer at the captured cursor.
--- One-shot: a successful paste disarms. Kept separate from init.lua so the
--- logic is testable without a socket/daemon.

local M = {}

---@class VoicedPasteTarget
---@field window_id integer
---@field bufnr integer
---@field line_base0 integer
---@field col_base0 integer

---@type VoicedPasteTarget|nil
local target = nil

--- Arm paste mode, capturing the cursor/buffer of the given window.
---@param win_id? integer # defaults to current window (0)
---@return boolean armed
function M.arm(win_id)
    win_id = win_id or 0
    local bufnr = vim.api.nvim_win_get_buf(win_id)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return false
    end

    local line_base1, col_base0 = unpack(vim.api.nvim_win_get_cursor(win_id))
    target = {
        window_id = win_id,
        bufnr = bufnr,
        line_base0 = line_base1 - 1,
        col_base0 = col_base0,
    }
    return true
end

---@return boolean
function M.is_armed()
    return target ~= nil
end

--- Disarm without pasting.
function M.cancel()
    target = nil
end

--- Insert `text` at the captured cursor position in the captured buffer.
--- Returns true and disarms on a successful paste.
---@param text string
---@return boolean pasted
function M.paste(text)
    if not target then
        return false
    end

    -- The target window may have been closed; fall back to the current window
    -- for cursor placement, but always insert into the captured buffer.
    local win_id = target.window_id
    if not vim.api.nvim_win_is_valid(win_id) then
        win_id = 0
    end

    local bufnr = target.bufnr
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return false
    end

    local insert_lines = vim.split(text, "\n")
    -- Insert at the captured cursor position (0-indexed line/col).
    vim.api.nvim_buf_set_text(
        bufnr,
        target.line_base0,
        target.col_base0,
        target.line_base0,
        target.col_base0,
        insert_lines
    )

    -- Move the cursor to just after the inserted text (on the target window).
    local new_line_base0 = target.line_base0 + #insert_lines - 1
    local new_col_base0 = #insert_lines[#insert_lines]
    vim.api.nvim_win_set_cursor(win_id, { new_line_base0 + 1, new_col_base0 })

    -- One-shot: disarm after a successful paste.
    target = nil
    return true
end

return M
