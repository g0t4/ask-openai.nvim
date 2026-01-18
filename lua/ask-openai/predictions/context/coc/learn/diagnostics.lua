local log = require("ask-openai.logs.logger").predictions()

local M = {}

---@param bufnr integer
---@return table[]
function M.get_coc_diagnostics_for_buffer(bufnr)
    log:info("bufnr", bufnr)
    local all_diagnostics = vim.fn.CocAction("diagnosticList")
    -- log:info(vim.inspect(all_diagnostics))
    return vim.iter(all_diagnostics)
        :filter(function(diag)
            return diag.bufnr == bufnr
        end)
        :totable()
end

-- *example from CocAction('diagnosticList')
--
-- {
--   bufnr = 7,
--   level = 1,
--   code = "reportArgumentType",
--   col = 39, end_col = 46,
--   lnum = 10, end_lnum = 10,
--   file = "/Users/wesdemos/repos/github/g0t4/private-auto-edit-suggests/auto_edit/new_silence/detects/crossings_tests.py",
--   location = {
--     range = {
--       ["end"] = { character = 45, line = 9 },
--       start = { character = 38, line = 9 }
--     },
--     uri = "file:///Users/wesdemos/repos/github/g0t4/private-auto-edit-suggests/auto_edit/new_silence/detects/crossings_tests.py"
--   },
--   message = 'Argument of type "list[Crossover]" cannot be assigned to parameter "x" of type "ArrayLike" in function "assert_array_equal"\n  Type "list[Crossover]" is not assignable to type "ArrayLike"\n    "list[Crossover]" is incompatible with protocol "Buffer"\n      "__buffer__" is not present\n    "list[Crossover]" is incompatible with protocol "_SupportsArray[dtype[Any]]"\n      "__array__" is not present\n    "list[Crossover]" is incompatible with protocol "_NestedSequence[_SupportsArray[dtype[Any]]]"\n      "__getitem__" is an incompatible type\n        No overloaded function matches type "(index: int, /) -> (_T_co@_NestedSequence | _NestedSequence[_T_co@_NestedSequence])"\n  ...',
--   severity = "Error",
--   source = "Pyright"
-- }

local function diagnostics_to_qflist(diagnostics)
    local qf = {}
    for _, diag in ipairs(diagnostics) do
        log:info("diag", vim.inspect(diag))
        table.insert(qf, {
            -- filename = vim.uri_to_fname(diag.location.uri),
            filename = diag.file,
            -- 1-based lnum/col
            lnum     = diag.lnum,
            col      = diag.col,
            --
            text     = diag.message,
            type     = ({
                Error = "E",
                Warning = "W",
                Information = "I",
                Hint = "H",
            })[diag.severity] or "E",
        })
    end
    return qf
end

function M.show_coc_diag_in_qflist()
    local bufnr = vim.api.nvim_get_current_buf()
    local diagnostics = M.get_coc_diagnostics_for_buffer(bufnr)
    if not diagnostics or vim.tbl_isempty(diagnostics) then
        vim.notify("No diagnostics from coc.nvim for current buffer", vim.log.levels.INFO)
        return
    end

    local qf = diagnostics_to_qflist(diagnostics)
    vim.fn.setqflist(qf, "r")
    vim.cmd("copen")
end

function M.setup()
    vim.api.nvim_create_user_command("CocQuickFix", M.show_coc_diag_in_qflist, { desc = "coc.nvim diagnostics into quickfix" })
    vim.keymap.set("n", "<C-q>", ":CocQuickFix<CR>", { silent = true })
end

return M
