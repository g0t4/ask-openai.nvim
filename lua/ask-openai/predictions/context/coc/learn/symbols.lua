-- I want to take that completion list from coc and feed it into the model too
--  that way the model can select from that list so I don't have to scroll down
--  and this is highly tailored to the context at hand...
--  and then I need to determine if this meaningfully helps with predictions
--    i.e. write a test suite, capture examples as I use coc where it would be nice for the model to pick the completion
--    wait... could I race a second completion with JUST coc current items...
--      and then maybe use that to auto highlight (not select) that item so I can hit enter to accept it?)
--      or ask for a confidence score and have it switch to that vs regular predictions?
--  could look into only passing this list if I switch on a mode to do so
--    i.e. advanced predictions that take longer but consider more context like coc, recent edtis, clipboard history, etc

-- TODO find out how to programatically access the list of completions shown by coc in the menu and pass to the model

local M = {}

local function get_symbol_at_cursor()
    -- 100% experimental here... just playing with APIs and finding what I want
    error "not yet implemented"

    -- local symbols = vim.fn.CocAction('documentSymbols')
    local symbols = vim.fn.CocAction('getWorkspaceSymbols')
    if not symbols or vim.tbl_isempty(symbols) then
        print('No symbols found')
        return
    end

    local cursor_position = vim.api.nvim_win_get_cursor(0)
    local my_line = cursor_position[1] - 1 -- 0-based
    local my_column = cursor_position[2]
    local my_uri = vim.uri_from_bufnr(0)
    print("my_uri: " .. my_uri)

    local function is_in_range_of_me(location)
        local uri = location.uri
        local s, e = location.range.start, location.range["end"]

        if uri ~= my_uri then return false end
        vim.print(location)
        if my_line < s.line or my_line > e.line then return false end
        if my_line == s.line and my_column < s.character then return false end
        if my_line == e.line and my_column > e.character then return false end
        return true
    end
    local function get_what(symbol)
        if symbol.text ~= nil then return "text: " .. symbol.text end
        if symbol.name then return "name: " .. symbol.name end
        if symbol.kind then return "kind: " .. symbol.kind end
        if symbol.textEdit then return "text edit" end
        -- return "unknown symbol: " .. vim.inspect(symbol)
    end

    for _, symbol in ipairs(symbols) do
        -- vim.print(get_what(symbol))
        -- vim.print((symbol))
        -- if symbol.location.range then
        --     vim.print("   " .. vim.inspect(symbol.location.range))
        -- end
        if symbol.location and is_in_range_of_me(symbol.location) then
            print('Symbol: ' .. get_what(symbol) .. ' (' .. symbol.kind .. ')')
        end
    end

    print('No symbol at cursor')
end

vim.api.nvim_create_user_command('CocSymbolAtCursor', get_symbol_at_cursor, {})

function M.print_cocs()
    get_symbol_at_cursor()
end

function M.setup()
    vim.api.nvim_create_user_command("AskDumpCocs", M.print_cocs, {})
end

return M
