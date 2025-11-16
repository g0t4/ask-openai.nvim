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
    self:mark_next_line(role == "user" and "AskUserRole" or "AskAssistantRole")
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

---Add a block of lines that should start folded.
---The lines will be appended to `turn_lines` and a fold entry will be recorded.
---@param lines string[]   -- lines to add
---@param hl_group string  -- optional highlight for the folded region header
function LinesBuilder:add_folded_lines(lines, hl_group)
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

---@param text string   -- text to append; may contain newlines (will be split on \n)
function LinesBuilder:append_text(text)
    local lines = vim.split(text, "\n")
    vim.list_extend(self.turn_lines, lines)
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

return LinesBuilder
