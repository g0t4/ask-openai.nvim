-- @class ChatThread
-- @see https://platform.openai.com/docs/api-reference/chat/create
-- @field messages ChatMessage[]
-- @field last_request LastRequest
local ChatThread = {}

function ChatThread:new()
    self = setmetatable({}, { __index = ChatThread })
    self.messages = {}
    self.last_request = nil
    return self
end

--- @param request LastRequest
function ChatThread:set_last_request(request)
    -- PRN consider moving this up a level to ctor as I would only need this the very first time..
    --  also maybe instead of using a body table I should start with a thread and pass that to curl_for
    request.thread = self -- TODO try this out
    self.last_request = request
    -- tmp way to copy over initial messages until I rewrite curl_for
    for _, message in ipairs(request.body.messages) do
        self:add_message(message)
    end
end

--- @param message ChatMessage
function ChatThread:add_message(message)
    if not message.role then
        error("message.role is required")
    end
    if not message.content then
        error("message.content is required")
    end
    table.insert(self.messages, message)
end

--- build the body of a curl request!
---    taking into account all messages
function ChatThread:to_body()
    local json_messages = {}
    -- PRN map to change shape to fit api endpoint? ... for now I think ChatMessage type already matches fully what is needed
    -- TODO ensure serializes correctly to json messages
    -- for _, message in ipairs(self.messages) do
    --     table.insert(json_messages, { role = message.role, content = message.content })
    -- end
    -- -- TODO other body components specific to the thread, if any?
    return vim.fn.json_encode({ messages = self.messages })
end

return ChatThread
