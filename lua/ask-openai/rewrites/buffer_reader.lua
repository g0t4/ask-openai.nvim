local M = {}

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

