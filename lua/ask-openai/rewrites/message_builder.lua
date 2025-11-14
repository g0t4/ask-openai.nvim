local files = require("ask-openai.helpers.files")
local buffers = require("ask-openai.helpers.buffers")
local ChatMessage = require("ask-openai.questions.chat_message")

---@class MessageBuilder
---@field private parts string[]
local MessageBuilder = {}
MessageBuilder.__index = MessageBuilder

---@return MessageBuilder
function MessageBuilder:new()
    local obj = { parts = {} }
    setmetatable(obj, self)
    return obj
end

---@param text string
---@return MessageBuilder
function MessageBuilder:plain_text(text)
    table.insert(self.parts, text)
    return self
end

---@return MessageBuilder
function MessageBuilder:md_current_buffer()
    local path = files.get_current_file_relative_path()
    local entire_file = buffers.get_text_in_current_buffer()
    self:md_code_block(path, entire_file)
    return self
end

---Append a markdown code block
---
---  ```foo.py
---  def code(self):
---      pass
---  ```
---@param filename string|nil file name or language identifier
---@param content string
---@return MessageBuilder
function MessageBuilder:md_code_block(filename, content)
    local header = "```"
    if filename and #filename > 0 then
        header = header .. filename
    end
    table.insert(self.parts, header .. "\n")
    table.insert(self.parts, content .. "\n")
    table.insert(self.parts, "```")
    return self
end

---Append a markdown heading
---@param level integer 1-6
---@param title string
---@return MessageBuilder
function MessageBuilder:md_header(level, title)
    -- TODO this is an IDEA - to prime me - get rid of this if not used
    level = math.max(1, math.min(6, level))
    table.insert(self.parts, string.rep("#", level) .. " " .. title .. "\n")
    return self
end

---Append a list item
---@param items string[] items to list
---@param ordered boolean|nil true for ordered list
---@return MessageBuilder
function MessageBuilder:md_list(items, ordered)
    -- TODO get rid of this if I don't use it
    for i, item in ipairs(items) do
        local prefix = ordered and (i .. ". ") or "- "
        table.insert(self.parts, prefix .. item .. "\n")
    end
    return self
end

---Build the final message string
---@return string
function MessageBuilder:to_text()
    return table.concat(self.parts, "\n")
end

---Build the final message in a ChatMessage package
---@return ChatMessage
function MessageBuilder:to_user_message()
    return ChatMessage:user(self:to_text())
end

return MessageBuilder
