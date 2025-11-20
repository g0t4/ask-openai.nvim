---@class ContextItem
---@field content string
---@field filename string
ContextItem = {}
ContextItem.__index = ContextItem

---@param content string
---@param filename string
---@return ContextItem
function ContextItem:new(content, filename)
    local instance = {
        content = content,
        filename = filename
    }
    setmetatable(instance, self)
    return instance
end

return ContextItem
