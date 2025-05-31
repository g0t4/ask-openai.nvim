local log = require("ask-openai.prediction.logger").predictions()

local Selection = {}

function Selection:new(selected_lines, start_line_1indexed, start_col_1indexed, end_line_1indexed, end_col_1indexed)
    local obj = {
        original_text = vim.fn.join(selected_lines, "\n"),
        start_line_1indexed = start_line_1indexed,
        start_col_1indexed = start_col_1indexed,
        end_line_1indexed = end_line_1indexed,
        end_col_1indexed = end_col_1indexed,
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
            "Selection: 0-indexed start(line=" .. (self.start_line_1indexed - 1)
            .. ",col=" .. (self.start_col_1indexed - 1)
            .. ") end(line=" .. (self.end_line_1indexed - 1)
            .. ",col=" .. (self.end_col_1indexed - 1)
            .. ") (" .. self.original_text .. ")"
    end
    return
        "Selection: 1-indexed start(line=" .. self.start_line_1indexed
        .. ",col=" .. self.start_col_1indexed
        .. ") end(line=" .. self.end_line_1indexed
        .. ",col=" .. self.end_col_1indexed
        .. ") (" .. self.original_text .. ")"
end

function Selection:log_info(as_0indexed)
    log:info(self:to_str(as_0indexed))
end

return Selection
