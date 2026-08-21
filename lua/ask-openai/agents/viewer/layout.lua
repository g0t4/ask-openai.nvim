--- Shared layout constants for the agents viewer windows.
--- The chat (history) window and the user input box are stacked vertically to
--- fill the whole usable screen without overlapping.
---
--- NOTES on float window geometry in Neovim:
---  * The config `height` is the *content* height; the border is drawn OUTSIDE
---    that area (1 row top + 1 row bottom).
---  * Floats positioned with `relative="editor"` can cover the tabline and
---    statusline, but CANNOT cover the command line. So the usable height is
---    `vim.o.lines - vim.o.cmdheight`.
local M = {}

--- Minimum content height (in rows) of the user input box at the bottom of the screen.
--- It grows from here to fit long prompts; see INPUT_HEIGHT_MAX_RATIO.
M.INPUT_HEIGHT = 3

--- Largest the user input box may grow to (ratio of the usable float area), so a
--- very long prompt never eats the whole screen. The chat (history) window keeps
--- whatever is left above it.
M.INPUT_HEIGHT_MAX_RATIO = 0.6

---@param name string
---@return integer? bufnr
function nvim_find_buf_by_name(name)
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.fn.match(vim.api.nvim_buf_get_name(bufnr), name) >= 0 then
            return bufnr
        end
    end
    return nil
end

--- The content height of the user input box, driven by its buffer's line count.
--- Grows with the typed prompt, clamped between INPUT_HEIGHT (compact, for quick
--- additions) and INPUT_HEIGHT_MAX_RATIO * editor_height() (room for long prompts).
---@return integer
function M.input_height()
    local bufnr = nvim_find_buf_by_name('AskAgentInput')
    if bufnr == nil then return M.INPUT_HEIGHT end
    return math.max(M.INPUT_HEIGHT, math.min(M.max_input_height(), vim.api.nvim_buf_line_count(bufnr)))
end

--- Maximum content height (in rows) of the user input box.
---@return integer
function M.max_input_height()
    return math.floor(M.editor_height() * M.INPUT_HEIGHT_MAX_RATIO)
end

--- Usable height (in rows) for `relative="editor"` float windows. Floats cannot
--- cover the command line, so we subtract `cmdheight` from the total screen rows.
---@return integer
function M.editor_height()
    return vim.o.lines - vim.o.cmdheight
end

return M
