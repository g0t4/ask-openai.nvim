---
-- Utility module to read buffer contents.
-- Provides two simple helpers:
--   * `current()` – returns the whole text of the current buffer as a string.
--   * `all()` – returns a table mapping buffer numbers (or names) to their full text.
--
-- Both helpers use the Neovim API directly and avoid any heavy dependencies.
-- The implementation mirrors the style of other helpers in `helpers/buffers.lua`.
---

local M = {}

--- Return the entire text of the current buffer as a single string.
-- The function concatenates lines with a newline character, preserving the file's
-- line endings as Neovim stores them (without the trailing newline on the last
-- line). This mirrors typical behaviour of `vim.api.nvim_buf_get_lines`.
function M.current()
  -- 0 refers to the current buffer, 0, -1 grabs all lines.
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return table.concat(lines, "\n")
end

--- Return a table with the full text of every listed buffer.
-- The returned table's keys are buffer numbers; each value is the buffer's
-- content as a string. Buffers that are not loaded or have no name are still
-- included – they may be empty but are safe to query.
function M.all()
  local result = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    -- Only include buffers that are listed (i.e., appear in the buffer list).
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_option(bufnr, "buflisted") then
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      result[bufnr] = table.concat(lines, "\n")
    end
  end
  return result
end

return M

