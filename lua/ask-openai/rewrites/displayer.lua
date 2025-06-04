local log = require("ask-openai.prediction.logger").predictions()
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
local extmarks_namespace_id = vim.api.nvim_create_namespace("ask-openai-rewrites")
local select_excerpt_mark_id = 11

function Displayer:new(_current_accept, _current_cancel)
    self = setmetatable({}, Displayer)
    self._current_cancel = _current_cancel
    self._current_accept = _current_accept
    self.window = WindowController:new_from_current_window()
    self.marks = ExtmarksSet:new(self.window:buffer().buffer_number, extmarks_namespace_id)
    self.removed_original_lines = false
    return self
end

function Displayer:clear_extmarks()
    self.marks:clear_all()
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

    -- Set extmark at the beginning of the selection
    vim.api.nvim_buf_set_extmark(
        0, -- Current buffer
        extmarks_namespace_id,
        selection:start_line_0indexed(),
        selection:start_col_0indexed(),
        {
            id = select_excerpt_mark_id,
            virt_text = first_line,
            virt_lines = virt_lines,
            virt_text_pos = "overlay",
            hl_mode = "combine"
        }
    )
end

---@diagnostic disable-next-line: unused-function
local function inspect_diff(diff)
    local lines = {}
    for _, v in ipairs(diff) do
        local type = v[1]
        local text = v[2]
        if type == "+" then
            text = ansi.green(text)
        elseif type == '-' then
            text = ansi.red(text)
        else
            text = ansi.white(text)
        end
        type = ansi.black(ansi.white_bg(type))
        local line = type .. " " .. text
        table.insert(lines, line)
    end
    return table.concat(lines, "\n")
end


---@param selection Selection
function Displayer:on_response(selection, lines)
    local lines_text = table.concat(lines, "\n")
    local diff = combined.combined_diff(selection.original_text, lines_text)
    -- log:info("diff:\n" .. inspect_diff(diff))

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

            local type_hlgroup = nil -- nil = TODO don't change it right?
            if type == '+' then
                -- type_hlgroup = hl_added -- mine (above)
                -- FYI nvim and plugins have a bunch of options already registerd too (color/highlight wise)
                -- type_hlgroup = "Added" -- light green
                type_hlgroup = 'diffAdded' -- darker green/cyan - *** FAVORITE
            elseif type == '-' then
                -- type_hlgroup = hl_deleted -- mine (above)
                -- type_hlgroup = "Removed" -- very light red (almost brown/gray)
                type_hlgroup = 'diffRemoved' -- dark red - *** FAVORITE
                -- return accum
                -- actually, based on how I aggregate between sames... there should only be one delete and one add between any two sames... so, I could just show both and it would appaer like remove / add (probably often lines removed then lines added, my diff processor puts the delete first which makes sense for that to be on top)
            end
            if not text:find('\n') then
                -- no new lines, so we just tack on to end of current line
                local len_text = #text
                if len_text > 0 then
                    table.insert(current_line, { text, type_hlgroup })
                end
            else
                -- TODO this needs testing, something could be buggy and it'd be very hard to find out
                local split_lines = vim.split(text, '\n')
                -- ? is split_lines the right name here? why did I use piece below and not line? (wes notes inline rewrites)
                -- log:info("split_lines:", vim.inspect(split_lines))
                for i, piece in ipairs(split_lines) do
                    -- FYI often v will be empty (i.e. a series of newlines)... do not exclude these empty lines!
                    local len_text = #piece
                    if len_text > 0 then
                        -- don't add empty pieces, just make sure we add the lines (even if empty)
                        table.insert(current_line, { piece, type_hlgroup })
                    end
                    if i < #split_lines then
                        -- ? why isn't this done on the last split line? (wes notes inline rewrites)
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

    -- TODO! do I need to support rewrites in the middle of a line? I doubt it... and right now the zeta rewrite is based on whole lines IIRC
    local start_line_0i = selection:start_line_0indexed()
    local end_line_0i = selection:end_line_0indexed()
    -- log:info("original selection: " .. selection:range_str_0indexed())


    -- log:info('extmark_lines')
    -- for _, v in ipairs(extmark_lines) do
    --     log:info(vim.inspect(v))
    -- end

    -- delete original lines (that way only diff shows in extmarks)
    if not self.removed_original_lines then
        -- keep in mind, doing this before/after set extmarks matters
        -- ? any issues with going past end of file for this end exclusive scenario?
        local end_line_exclusive_0i = end_line_0i + 1
        self.window:buffer():replace_lines(
            start_line_0i,
            end_line_exclusive_0i, -- exclusive of this line
            -- insert a blank line, to overlay first_extmark_line, then rest of extmark_lines are below it
            { "", "" })
        self.removed_original_lines = true
    end

    local first_extmark_line = table.remove(extmark_lines, 1)

    self.marks:set(select_excerpt_mark_id, {
        start_line = start_line_0i,
        start_col = 0, -- TODO! allow intra line selections too
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
    -- TODO get rid of fallbacks? Alt-Tab/Esc shouldn't be needed
    vim.cmd([[
      silent! iunmap <buffer> <Tab>
      silent! iunmap <buffer> <Esc>

      silent! nunmap <buffer> <Tab>
      silent! nunmap <buffer> <Esc>
    ]])
end

return Displayer
