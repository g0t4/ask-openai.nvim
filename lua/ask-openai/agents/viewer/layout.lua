--- Shared layout constants for the agents viewer windows.
--- The chat (history) window and the user input box are stacked vertically to
--- fill the whole screen without overlapping.
local M = {}

--- Height (in rows, including the window border) reserved at the bottom for the
--- user input box. The chat window fills the remaining space above it.
M.INPUT_HEIGHT = 5

return M
