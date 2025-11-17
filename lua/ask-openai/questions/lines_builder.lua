local HLGroups = require("ask-openai.hlgroups")

---@class LinesBuilder
---@field turn_lines string[]
---@field marks table[]
---@field marks_ns_id number
local LinesBuilder = {}
LinesBuilder.__index = LinesBuilder

---@return LinesBuilder
function LinesBuilder:new(marks_ns_id)
    local self = setmetatable({
        turn_lines = {},
        marks = {},
        marks_ns_id = marks_ns_id
    }, LinesBuilder)
    return self
end

-- TODO ?? develop a simple treesitter grammar to control styling (colors) and folding
--   ideas: https://chatgpt.com/c/69174d02-b1fc-8333-b8a6-6ecace15a383
-- that way I can stop tracking ranges and just add content!

--- FYI DO NOT call this in a fast-event handler
function LinesBuilder:create_marks_namespace()
    local timestamp = vim.loop.hrtime()
    local ns_name = "Ask_Marks_" .. timestamp
    self.marks_ns_id = vim.api.nvim_create_namespace(ns_name)
end

---@param hl_group string
function LinesBuilder:mark_next_line(hl_group)
    local start_line_base0 = #self.turn_lines

    table.insert(self.marks, {
        start_line_base0 = start_line_base0,
        start_col_base0 = 0,
        end_line_base0 = start_line_base0 + 1,
        end_col_base0 = 0,
        hl_group = hl_group
    })
end

---@param role string
function LinesBuilder:append_role_header(role)
    self:mark_next_line(role == "user" and HLGroups.USER or HLGroups.ASSISTANT)
    table.insert(self.turn_lines, role)
end

function LinesBuilder:append_styled_text(text, hl_group)
    local lines = vim.split(text, "\n")
    self:append_styled_lines(lines, hl_group)
end

---@param lines string[]
function LinesBuilder:append_styled_lines(lines, hl_group)
    local start_line_base0 = #self.turn_lines
    local mark = {
        start_line_base0 = start_line_base0, -- base0 b/c next line is the marked one (thus not yet in line count)
        start_col_base0 = 0,
        end_line_base0 = start_line_base0 + #lines, -- IIAC I want end exclusive
        end_col_base0 = 0, -- or, #lines[#lines], to stop on last line (have to -1 on end line too)
        hl_group = hl_group
    }
    table.insert(self.marks, mark)
    vim.list_extend(self.turn_lines, lines)
end

---@param text string
---@param hl_group string
function LinesBuilder:append_folded_styled_text(text, hl_group)
    local lines = vim.split(text, "\n")
    self:append_folded_styled_lines(lines, hl_group)
end

---a block lines that should start folded.
---The lines will be appended to `turn_lines` and a fold entry will be recorded.
---@param lines string[]
---@param hl_group string  -- optional highlight for the folded region header
function LinesBuilder:append_folded_styled_lines(lines, hl_group)
    local start_line_base0 = #self.turn_lines
    local mark = {
        start_line_base0 = start_line_base0, -- base0 b/c next line is the marked one (thus not yet in line count)
        start_col_base0 = 0,
        end_line_base0 = start_line_base0 + #lines, -- IIAC I want end exclusive
        end_col_base0 = 0, -- or, #lines[#lines], to stop on last line (have to -1 on end line too)
        hl_group = hl_group,
        fold = true
    }
    table.insert(self.marks, mark)
    vim.list_extend(self.turn_lines, lines)
end

function LinesBuilder:append_unexpected_line(one_line)
    self:append_styled_lines({ one_line }, HLGroups.UNEXPECTED_MESSAGE)
end

function LinesBuilder:append_unexpected_text(text)
    self:append_styled_text(text, HLGroups.UNEXPECTED_MESSAGE)
end

---@param text string   -- text to append; may contain newlines (will be split on \n)
function LinesBuilder:append_text(text)
    local lines = vim.split(text, "\n")
    vim.list_extend(self.turn_lines, lines)
end

---@param lines string[]
function LinesBuilder:append_lines(lines)
    vim.list_extend(self.turn_lines, lines)
end

---@param one_line string - named to be noticeable given similarity in _lines functions
function LinesBuilder:append_line(one_line)
    -- TODO verify working with table.insert
    table.insert(self.turn_lines, one_line)
end

---Append a blank line unconditionally.
function LinesBuilder:append_blank_line()
    table.insert(self.turn_lines, "")
end

---Append a blank line only if the last line is not already blank.
function LinesBuilder:append_blank_line_if_last_is_not_blank()
    local last = self.turn_lines[#self.turn_lines]
    if not last or last ~= "" then
        table.insert(self.turn_lines, "")
    end
end

---@param text string
---@param max_lines? integer
function LinesBuilder:append_STDERR(text, max_lines)
    --TODO color red
    -- show all, always?
end

---@param text string
---@param max_lines? integer
function LinesBuilder:append_STDOUT(text, max_lines)
    -- TODO! add some unit tests to flesh out bugs (b/c breaking an agent workflow would suck!)

    max_lines = max_lines or 3
    -- ?? double threshold ?
    --   #lines > 5 => show 3 max
    --   #lines <= 5 => show all

    local lines = vim.split(text, "\n")
    if #lines == 0 then
        return
    elseif #lines == 1 then
        local oneliner = "STDOUT: " .. lines[1]
        -- PRN style the STDOUT as subset of line (use column offsets)
        self:append_styled_lines({ oneliner }, HLGroups.TOOL_STDOUT_CONTENT)
        return
    elseif #lines == 2 and lines[2] == "" then
        -- last line is blank b/c of \n on end of STDOUT

        local oneliner = "STDOUT: " .. lines[1]
        -- PRN style the STDOUT as subset of line (use column offsets)
        self:append_styled_lines({ oneliner }, HLGroups.TOOL_STDOUT_CONTENT)
        return
    end

    -- PRN parent fold around entire section (that way I can collapse on-demand...
    -- this would be good to add with a TS grammar so I am not doing even more work to mark ranges and another fold level)

    -- TODO do I really want this to be colorful? can I just show the output w/o a header? i.e. depending on what else was present in content array?
    --    TODO in this case I need to handle the entire command on its own? so it can control rest of content?
    self:append_styled_lines({ "STDOUT" }, HLGroups.TOOL_STDOUT_HEADER)

    -- first max_lines (default 3) are not collapsed
    local visible_lines = vim.list_slice(lines, 1, max_lines)
    local folded_lines = vim.list_slice(lines, max_lines + 1, #lines)

    self:append_styled_lines(visible_lines, HLGroups.TOOL_STDOUT_CONTENT)

    -- Add the folded remainder as a child fold
    if #folded_lines > 0 then
        self:append_folded_styled_lines(folded_lines, "") -- foldtext blank or custom
        -- TODO ask a tiny model to summarize the lines!
    end
end

return LinesBuilder
