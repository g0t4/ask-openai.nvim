-- TODO this is a reminder, put coc related context item providers here
--
--
--  maybes:
--   vim.fn.CocAction('diagnosticInfo') [target]  ... suppposed to be able to get diagnostics for current cursor position (IIUC)
--      how do I pass target? is it a lnum/col?
--         :h coc-actions
--      add a /diag to slash context commands
--   CocAction('diagnosticList')
--      returns for entire workspace, can filter on bufnr/file (see learn/diagnostics.lua examples)
--   CocAction('documentSymbols')
--   CocAction('workspaceSymbols')

local M = {}

function M.setup()
end

return M
