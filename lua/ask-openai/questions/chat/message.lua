local log = require('ask-openai.logs.logger').predictions()
local ansi = require('ask-openai.prediction.ansi')

---@class ChatMessage
---@field role? string
---@field index integer -- must be kept and sent back with thread
---@field content? string
---@field _verbatim_content? string -- hack for  <tool_call>... leaks (can be removed if fixed)
---@field reasoning_content? string
---@field finish_reason? string|vim.NIL -- FYI use get_finish_reason() for clean value (vim.NIL => nil)
---@field tool_call_id? string
---@field name? string
---@field tool_calls ToolCall[] -- empty if none
local ChatMessage = {}

--- FYI largely a marker interface as well, don't need to actually use this ctor
---@return ChatMessage
function ChatMessage:new(role, content)
    self = setmetatable({}, { __index = ChatMessage })
    self.role = role
    self.content = content
    self.finish_reason = nil
    self.tool_calls = {} -- empty == None (enforce invariant)
    -- PRN enforce content is string here?
    return self
end

function ChatMessage:new_tool_response(content, tool_call_id, name)
    self = ChatMessage:new("tool", content)
    --PRN enforce strings are not empty?
    self.tool_call_id = tool_call_id
    self.name = name
    return self
end

function ChatMessage:user(content)
    return ChatMessage:new("user", content)
end

function ChatMessage:assistant(content)
    return ChatMessage:new("assistant", content)
end

function ChatMessage:new_system_message(content)
    return ChatMessage:new("system", content)
end

function ChatMessage:add_tool_call_requests(call_request)
    -- ONLY clone fields on the original call request from the model
    local new_call = {
        id = call_request.id,
        index = call_request.index,
        type = call_request.type,
        ["function"] = {
            name = call_request["function"].name,
            arguments = call_request["function"].arguments,
        }
    }
    table.insert(self.tool_calls, new_call)
end

---@return string
function ChatMessage:dump_text()
    local lines = {
        ansi.white_bold(self.role .. ":") .. " " .. tostring(self.content or ""),
    }
    -- include fields not explicitly in the template above
    for key, v in pairs(self) do
        if key ~= "__index" and key ~= "role" and key ~= "content" then
            local color_key = ansi.yellow(key)
            local line = string.format("%s: %s", color_key, vim.inspect(v))
            table.insert(lines, line)
        end
    end
    return table.concat(lines, "\n")
end

---@enum FINISH_REASONS
ChatMessage.FINISH_REASONS = {
    LENGTH = "length",
    STOP = "stop",
    TOOL_CALLS = "tool_calls",
    -- observed finish_reason values: "tool_calls", "stop", "length", null (not string, a literal null JSON value)
    -- vim.NIL (still streaming) => b/c of JSON value of null (not string, but literal null in the JSON)

    -- FYI find finish_reason observed values:
    --   grep --no-filename -o '"finish_reason":[^,}]*' **/* 2>/dev/null | sort | uniq
    -- "finish_reason":"length"
    -- "finish_reason":"stop"
    -- "finish_reason":"tool_calls"
    -- "finish_reason":null
}

---Returns the finish reason, cleanup when not set (i.e. nil instead of vim.NIL)
---@return FINISH_REASONS?
function ChatMessage:get_finish_reason()
    if self.finish_reason == vim.NIL then
        return nil
    end
    return self.finish_reason
end

---@return boolean
function ChatMessage:is_still_streaming()
    return self.finish_reason == nil or self.finish_reason == vim.NIL
end

return ChatMessage
