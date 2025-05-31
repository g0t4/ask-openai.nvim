local log = require("ask-openai.prediction.logger").predictions()

---@class Selection
---@field original_text string
local Selection = {}

function Selection:new(selected_lines, start_line_1indexed, start_col_1indexed, end_line_1indexed, end_col_1indexed)
    local obj = {
        original_text = vim.fn.join(selected_lines, "\n"),
        -- FYI these are all private, will have accessors ultimatley to get 0 or 1 based?
        _start_line_0indexed = start_line_1indexed - 1,
        _start_col_0indexed = start_col_1indexed - 1,
        _end_line_0indexed = end_line_1indexed - 1,
        _end_col_0indexed = end_col_1indexed - 1,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

-- TODO add some tests of working with selection!!! YES
function Selection:is_empty()
    return self.original_text == nil or self.original_text == ""
end

function Selection:to_str(as_0indexed)
    as_0indexed = as_0indexed or false
    if as_0indexed then
        return
            "Selection: 0-indexed start(line=" .. (self._start_line_0indexed)
            .. ",col=" .. (self._start_col_0indexed)
            .. ") end(line=" .. (self._end_line_0indexed)
            .. ",col=" .. (self._end_col_0indexed)
            .. ") (" .. self.original_text .. ")"
    end
    return
        "Selection: 1-indexed start(line=" .. (self:start_line_0indexed() + 1)
        .. ",col=" .. (self:start_col_0indexed() + 1)
        .. ") end(line=" .. (self:end_line_0indexed() + 1)
        .. ",col=" .. (self:end_col_0indexed() + 1)
        .. ") (" .. self.original_text .. ")"
end

function Selection:start_line_0indexed()
    return self._start_line_0indexed
end

function Selection:start_col_0indexed()
    return self._start_col_0indexed
end

function Selection:end_line_0indexed()
    return self._end_line_0indexed
end

function Selection:end_col_0indexed()
    return self._end_col_0indexed
end

function Selection:log_info(message, as_0indexed)
    log:info(message, self:to_str(as_0indexed))
end

return Selection
