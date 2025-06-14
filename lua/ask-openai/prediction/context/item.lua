ContextItem = {}
ContextItem.__index = ContextItem

function ContextItem:new(content, filename)
    local instance = {
        content = content,
        filename = filename
    }
    setmetatable(instance, self)
    return instance
end

return ContextItem
