local M = {}

---@class BufferState
---@field is_active boolean
---@field counter integer
local BufferState = {}
BufferState.__index = BufferState

function BufferState:new()
    return setmetatable({
        is_active = false,
        counter = 0,
    }, self)
end

--- Global registry: bufnr -> BufferState instance
local buffer_states = {}

--- Cleanup when buffer is deleted
vim.api.nvim_create_autocmd("BufDelete", {
    callback = function(args)
        buffer_states[args.buf] = nil
    end,
})

local M = {}

---@param bufnr integer
---@return BufferState
function M.buffer_state_for(bufnr)
    if not buffer_states[bufnr] then
        buffer_states[bufnr] = BufferState:new()
    end
    return buffer_states[bufnr]
end

return M
