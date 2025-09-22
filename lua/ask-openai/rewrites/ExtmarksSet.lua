---@class ExtmarksSet
---@field buffer_number number
---@field namespace_id number
local ExtmarksSet = {}
ExtmarksSet.__index = ExtmarksSet

---@param buffer_number integer
---@param ns string
---@return ExtmarksSet
function ExtmarksSet:new(buffer_number, ns)
    self = setmetatable({}, ExtmarksSet)
    self.buffer_number = buffer_number
    self.namespace_id = vim.api.nvim_create_namespace(ns)
    return self
end

function ExtmarksSet:clear_all()
    -- FYI 0 => -1 == all lines
    vim.api.nvim_buf_clear_namespace(self.buffer_number, self.namespace_id, 0, -1)
end

--- get an extmark by id
--- @param mark_id integer
---@return vim.api.keyset.get_extmark_item_by_id # 0-indexed (row, col) tuple or empty list ()
function ExtmarksSet:get(mark_id)
    -- FYI probably it's more useful to cache this in the consumer, unless multiple consumers can change it
    return vim.api.nvim_buf_get_extmark_by_id(self.buffer_number, self.namespace_id, mark_id, {})
end

--- create OR update (i.e. move) an existing mark
--- @param mark_id integer
--- @param opts { start_line:integer, start_col:integer, ... } # nvim_buf_set_extmark options
---@return integer mark_id # useful if you didn't provide a mark_id and want the generated id
function ExtmarksSet:set(mark_id, opts)
    opts.id = mark_id

    local start_line = opts.start_line or 0
    local start_col = opts.start_col or 0
    opts.start_line = nil
    opts.start_col = nil


    return vim.api.nvim_buf_set_extmark(
        self.buffer_number, self.namespace_id,
        start_line, start_col,
        opts)
end

return ExtmarksSet
