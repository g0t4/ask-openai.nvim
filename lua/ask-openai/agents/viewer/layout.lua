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

--- Content height (in rows) of the user input box at the bottom of the screen.
--- With its border the box takes INPUT_HEIGHT + 2 rows of screen space.
M.INPUT_HEIGHT = 3

--- Usable height (in rows) for `relative="editor"` float windows. Floats cannot
--- cover the command line, so we subtract `cmdheight` from the total screen rows.
---@return integer
function M.editor_height()
    return vim.o.lines - vim.o.cmdheight
end

return M
