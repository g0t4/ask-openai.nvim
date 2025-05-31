local log = require("ask-openai.prediction.logger").predictions()
local Selection = require("ask-openai.helpers.selection")
local M = {}

function M.get_visual_selection()
    -- TODO! get tests of this in place using plenary... with a real buffer
    -- TODO! the issue w/ extra trailing char left behind might have to do with this logic?

    -- FYI getpos returns a byte index, getcharpos() returns a char index (prefer it)
    --   getcharpos also resolves the issue with v:maxcol as the returned col number (i.e. in visual line mode selection)
    local _, start_line_1indexed, start_col_1indexed, _ = unpack(vim.fn.getcharpos("'<"))
    -- start_line/start_col are 1-indexed (from register value)
    local _, end_line_1indexed, end_col_1indexed, _ = unpack(vim.fn.getcharpos("'>"))
    if start_line_1indexed == 0 and start_col_1indexed == 0 and end_line_1indexed == 0 and end_col_1indexed == 0 then
        -- log:info("no selection, using cursor position with empty selection")
        local row_1indexed, col_0indexed = unpack(vim.api.nvim_win_get_cursor(0))
        start_line_1indexed = row_1indexed
        start_col_1indexed = col_0indexed + 1
        -- copy to end position
        end_line_1indexed = start_line_1indexed
        end_col_1indexed = start_col_1indexed
        return Selection:new({}, start_line_1indexed, start_col_1indexed, end_line_1indexed, end_col_1indexed)
    end

    -- end_line/end_col are 1-indexed, end_col appears to be the cursor position at the end of a selection
    --
    -- FYI, while in visual modes (char/line) the current selection is NOT the last selection
    --   if this lua func is called from a keymap using a lua handler, the WIP selection won't be available yet
    --   but, if this func is called indirectly via a vim command, the selection is "committed" as last selection
    --   executing a command logically seems like finalizing the selection, so that makes sense
    --   also, I get the rationale that calling a func is useful b/c that func could help move the cursor to select desired text and so you won't want to "commit" it yet
    --
    -- key modes (at least) to consider:
    --   normal mode
    --   visual linewise, charwise and blockwise
    --   select mode
    --
    -- TESTs for visual line mode:
    -- - empty line selected (not across to next line) -- has end_line = start_line
    -- - empty line selected by shift+V j    -- has end_line > start_line
    -- PRN add unit tests if this gets more complicated
    --
    -- FYI :h selection (vim.o.selection) => visual/select modes:
    --   right now selection value=inclusive in my config
    --   inclusive=yes/no is last char of selection included
    --   "past line"=yes/no
    --   tackle this (if its even an issue) when I encounter a problem with it
    --

    -- getline is 1-indexed, end-inclusive (optional)
    local selected_lines = vim.fn.getline(start_line_1indexed, end_line_1indexed)

    if #selected_lines == 0 then
        log:info("HOW DID WE GET HERE!? this shouldn't happen!")
        return Selection:new({}, start_line_1indexed, start_col_1indexed, end_line_1indexed, end_col_1indexed)
    end

    -- Truncate the last line to the specified end column
    local last_line = selected_lines[#selected_lines]
    selected_lines[#selected_lines] = string.sub(last_line, 1, end_col_1indexed)

    -- Truncate the first line thru the specified start column
    local first_line = selected_lines[1]
    selected_lines[1] = string.sub(first_line, start_col_1indexed)

    local selection = Selection:new(selected_lines, start_line_1indexed, start_col_1indexed, end_line_1indexed, end_col_1indexed)
    selection:log_info("get_visual_selection():")
    return selection
end

function M.get_current_buffer_entire_text()
    -- PRN take buffer_number
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    return table.concat(lines, "\n")
end

function M.dump_last_seletion()
    local selection = M.get_visual_selection()
    print(vim.inspect(selection))
end

function table_insert_many(tbl, items)
    for _, item in ipairs(items) do
        table.insert(tbl, item)
    end
end

function table_insert_split_lines(tbl, text)
    table_insert_many(tbl, vim.split(text, "\n"))
end

return M
