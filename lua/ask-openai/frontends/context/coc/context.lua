-- TODO this is a reminder, put coc related context item providers here
--  maybes:
--   CocAction('documentSymbols')
--   CocAction('workspaceSymbols')

local M = {}

function M.setup()
end

function M.diagnostic_under_cursor()
    -- :h coc-actions

    -- slash commands?
    -- /diagc[ursor] -- only diagnostics under cursor: ?? vim.fn.CocAction('diagnosticInfo', 'echo') ??
    -- /diagw[orkspace] -- everything from CocAction('diagnosticList')
    -- /diagf[ile] -- match on bufnr/file to filter CocAction('diagnosticList')
end

return M
