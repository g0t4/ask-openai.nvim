local log = require("ask-openai.logs.logger").predictions()
local combined = require("devtools.diff.combined")
local ExtmarksSet = require("ask-openai.rewrites.ExtmarksSet")
local WindowController = require("ask-openai.rewrites.WindowController")
local inspect = require("devtools.inspect")
local ansi = require("devtools.ansi")

---@class Displayer
local Displayer = {}
Displayer.__index = Displayer

local hlgroup = "AskRewrite"
vim.api.nvim_command("highlight default " .. hlgroup .. " guifg=#ccffcc ctermfg=green")
local select_excerpt_mark_id = 11
local explain_error_mark_id = 31

local hlgroup_error = "AskRewriteError"
vim.api.nvim_command("highlight default " .. hlgroup_error .. " guibg=#ff7777 guifg=#000000 ctermbg=red ctermfg=black")

function Displayer:new(_current_accept, _current_cancel)
    self = setmetatable({}, Displayer)
    self._current_cancel = _current_cancel
    self._current_accept = _current_accept
    self.window = WindowController:new_from_current_window()
    self.marks = ExtmarksSet:new(self.window:buffer().buffer_number, "AskRewriteExtmarks")
    self.error_marks = ExtmarksSet:new(self.window:buffer().buffer_number, "AskRewriteErrorExtmarks")
    self.removed_original_lines = false
    return self
end

function Displayer:clear_extmarks()
    self.marks:clear_all()
    self.error_marks:clear_all()
end

---@param selection Selection
---@param lines string[]
---@diagnostic disable-next-line: unused-function
function Displayer:show_green_preview_text(selection, lines)
    if #lines == 0 then
        self:clear_extmarks()
        return
    end

    local first_line = { { table.remove(lines, 1), hlgroup } }

    -- Format remaining lines for virt_lines
    local virt_lines = {}
    for _, line in ipairs(lines) do
        table.insert(virt_lines, { { line, hlgroup } })
    end

    self.marks:set(select_excerpt_mark_id, {

        -- Set extmark at the beginning of the selection
        start_line = selection:start_line_0indexed(),
        start_col = selection:start_col_0indexed(),

        virt_text = first_line,
        virt_lines = virt_lines,
        virt_text_pos = "overlay",
        hl_mode = "combine"
    })
end

---@param selection Selection
---@param new_text string
function Displayer:explain_error(selection, new_text)
    -- FYI quick hack for showing multiple errors
    --   test by using tools w/o --jinja flag server side => both STDOUT and STDERR have useful error messages
    --   => tools = tool_router.openai_tools()
    self._hack_previous_error_text = self._hack_previous_error_text or ""
    self._hack_previous_error_text = self._hack_previous_error_text .. '\n' .. new_text
    -- FYI I can polish this later, if it matters!
    -- by the way I love how these errors show!

    -- ?? any utility in leaving other extmarks too? i.e. failure mid generation? (probably not but just a thought)
    -- self:clear_extmarks()
    local lines = vim.split(self._hack_previous_error_text, '\n')
    local first_line = { { table.remove(lines, 1), "AskRewriteError" } }
    local virt_lines = {}
    for _, line in ipairs(lines) do
        table.insert(virt_lines, { { line, "AskRewriteError" } })
    end

    self.error_marks:set(explain_error_mark_id, {
        start_line = selection:start_line_0indexed(),
        start_col = selection:start_col_0indexed(),

        virt_text = first_line,
        virt_lines = virt_lines,
        virt_text_pos = "overlay",
        hl_mode = "combine"
    })
end

---@param selection Selection
function Displayer:on_response(selection, lines)
    local lines_text = table.concat(lines, "\n")
    local diff = combined.combined_word_diff(selection.original_text, lines_text)

    local extmark_lines = vim.iter(diff):fold({ {} }, function(accum, chunk)
        if chunk == nil then
            log:info('nil chunk: ' .. tostring(chunk))
        else
            -- each chunk has has two strings: { "type", "text\nfoo\nbar" }
            --   type == "same", "add", "del"
            -- text must be split on new line into an array
            --  when \n is encountered, start a new line in the accum
            local current_line = accum[#accum]
            local type = chunk[1]
            local text = chunk[2]

            local type_hlgroup = nil
            if type == '+' then
                type_hlgroup = 'diffAdded'
            elseif type == '-' then
                type_hlgroup = 'diffRemoved'
            end
            if not text:find('\n') then
                -- no new lines, so we just tack on to end of current line
                local len_text = #text
                if len_text > 0 then
                    table.insert(current_line, { text, type_hlgroup })
                end
            else
                local split_lines = vim.split(text, '\n')
                for i, piece in ipairs(split_lines) do
                    local len_text = #piece
                    if len_text > 0 then
                        -- don't add empty pieces, just make sure we add the lines (even if empty)
                        table.insert(current_line, { piece, type_hlgroup })
                    end
                    if i < #split_lines then
                        -- start a new, empty line (even if last piece was empty)
                        current_line = {}
                        accum[#accum + 1] = current_line
                        -- next piece will be first, which could be next in splits OR a subsequent chunk
                    end
                end
            end
        end
        return accum
    end)

    -- check if last group is empty, remove if so
    local last_line = extmark_lines[#extmark_lines]
    if #last_line < 1 then
        table.remove(extmark_lines, #extmark_lines)
    end

    if #extmark_lines < 1 then
        log:info('no lines')
        return
    end

    local start_line_0i = selection:start_line_0indexed()
    local end_line_0i = selection:end_line_0indexed()

    -- delete original lines (that way only diff shows in extmarks)
    if not self.removed_original_lines then
        -- keep in mind, doing this before/after set extmarks matters
        self.window:buffer():replace_lines(
            start_line_0i,
            end_line_0i, -- inclusive
            -- insert a blank line, to overlay first_extmark_line, then rest of extmark_lines are below it
            { "", "" })
        self.removed_original_lines = true
    end

    local first_extmark_line = table.remove(extmark_lines, 1)

    self.marks:set(select_excerpt_mark_id, {
        start_line = start_line_0i,
        start_col = 0,
        virt_text = first_extmark_line,
        virt_lines = extmark_lines,
        virt_text_pos = 'overlay',
    })

    self:set_keymaps()
end

function Displayer:accept()
    vim.schedule(function()
        log:info('Accepting')
        self:remove_keymaps()
        self:clear_extmarks()
        self._current_accept()
    end)
end

function Displayer:reject()
    vim.schedule(function()
        log:info('Rejecting')
        self:remove_keymaps()
        self:clear_extmarks()

        -- * reverse the removed lines
        vim.cmd("undo")

        self._current_cancel()
    end)
end

function Displayer:set_keymaps()
    vim.keymap.set({ 'i', 'n' }, '<Tab>', function() self:accept() end, { expr = true, buffer = true })
    vim.keymap.set({ 'i', 'n' }, '<Esc>', function() self:reject() end, { expr = true, buffer = true })
end

function Displayer:remove_keymaps()
    vim.cmd([[
      silent! iunmap <buffer> <Tab>
      silent! iunmap <buffer> <Esc>

      silent! nunmap <buffer> <Tab>
      silent! nunmap <buffer> <Esc>
    ]])
end

return Displayer
