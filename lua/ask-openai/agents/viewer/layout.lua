--- Shared layout constants for the agents viewer windows.
--- The chat (history) window and the user input box are stacked vertically to
--- fill the whole screen without overlapping.
---
--- IMPORTANT: for a float window, the config `height` is the *content* height;
--- the border is drawn OUTSIDE that area (1 row top + 1 row bottom). All heights
--- here are content heights.
local M = {}

--- Content height (in rows) of the user input box at the bottom of the screen.
--- With its border the box takes INPUT_HEIGHT + 2 rows of screen space.
M.INPUT_HEIGHT = 3

return M
