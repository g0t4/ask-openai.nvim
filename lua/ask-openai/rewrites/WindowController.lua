local BufferController0Indexed = require('ask-openai.rewrites.BufferController')
local log = require("devtools.logs.logger"):universal()

---This entire class operates on 0-indexed row and column positions
---   if that seems wrong I'll go to all 1-indexed
---Also intended to hide away complexities in nvim_ apis
---  i.e. tracking window ids, buffer numbers
---@class WindowController0Indexed
---@field window_id integer
local WindowController0Indexed = {}
-- just add setmetatable if you want to have a new super type for this too
WindowController0Indexed.__index = WindowController0Indexed

---@param window_id integer
function WindowController0Indexed:new(window_id)
    assert(self ~= nil) -- I want everything to pass self (force it so "inheritance" works)
    -- inherit the functionality of self
    -- local instance = setmetatable(self, WindowController0Indexed)
    local instance = self -- assume self already has __index that points to WindowController0Indexed
    instance.window_id = window_id
    return instance
end

---@param window_id integer
function WindowController0Indexed.standalone_controller_for(window_id)
    -- intentionally pass new table here b/c this method is intended for standalone controller instances (not inheriting, use new for that)
    local instance = WindowController0Indexed.new({}, window_id)
    setmetatable(instance, WindowController0Indexed) -- works b/c we set WindowController0Indexed.__index to itself above
    return instance
end

function WindowController0Indexed.standalone_controller_for_current_window()
    local current_window_id = vim.api.nvim_get_current_win()
    return WindowController0Indexed.standalone_controller_for(current_window_id)
end

---@return integer row_base0 # 0-indexed
---@return integer column_base0 # 0-indexed
function WindowController0Indexed:get_cursor_position()
    -- keep in mind different windows w/ same buffer have their own cursor positions
    -- that's why this is window specific
    -- get_cursor returns 1-indexed row, 0-indexed column
    local pos = vim.api.nvim_win_get_cursor(self.window_id)
    -- ? do I prefer to use a table or two return values?
    return pos[1] - 1, pos[2]
end

---@return integer row 0-indexed
function WindowController0Indexed:get_cursor_row()
    local row, _ = self:get_cursor_position()
    return row
end

---@return integer column 0-indexed
function WindowController0Indexed:get_cursor_column()
    local _, column = self:get_cursor_position()
    return column
end

---@param row integer 0-indexed
---@param column integer 0-indexed
function WindowController0Indexed:set_cursor_position(row, column)
    vim.api.nvim_win_set_cursor(self.window_id, { row + 1, column })
end

function WindowController0Indexed:set_cursor_at_end_of_last_line()
    local buffer = self:buffer()
    local num_lines_base1 = vim.api.nvim_buf_line_count(buffer.buffer_number)
    local last_line_base0 = num_lines_base1 - 1
    local last_line = vim.api.nvim_buf_get_lines(buffer.buffer_number, last_line_base0, last_line_base0 + 1, false)[1]
    local len_of_last_line_base0 = #last_line

    vim.api.nvim_win_set_cursor(self.window_id, { num_lines_base1, len_of_last_line_base0 })
end

function WindowController0Indexed:buffer()
    -- old troubleshooting code for some issues around invalid window_ids
    -- logs.trace('getting buffer for window ' .. self.window_id)
    -- log:info('windows: ' .. vim.inspect(vim.api.nvim_list_wins()))
    -- nvim_helpers.dump_windows()
    -- nvim_helpers.dump_buffers()
    local buffer_number = vim.api.nvim_win_get_buf(self.window_id)
    return BufferController0Indexed.for_buffer(buffer_number)
end

function WindowController0Indexed:get_node_at_cursor()
    local row, column = self:get_cursor_position()
    return self:buffer():get_node_at_position(row, column)
end

return WindowController0Indexed
