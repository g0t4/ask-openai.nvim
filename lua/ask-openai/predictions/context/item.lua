---@class ContextItem
---@field filename string
---@field content string
ContextItem = {}
ContextItem.__index = ContextItem

---@param filename string
---@param content string
---@return ContextItem
function ContextItem:new(filename, content)
    local instance = {
        content = content,
        filename = filename
    }
    setmetatable(instance, self)
    return instance
end

return ContextItem
