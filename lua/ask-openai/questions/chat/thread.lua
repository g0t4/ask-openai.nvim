local log = require('ask-openai.logs.logger').predictions()

--- see https://platform.openai.com/docs/api-reference/chat/create
---@class ChatThread
---@field messages TxChatMessage[]
---@field params ChatParams
---@field last_request CurlRequestForThread
---@field base_url string
local ChatThread = {}

---@param params ChatParams
---@param base_url string
---@return ChatThread
function ChatThread:new(params, base_url)
    self = setmetatable({}, { __index = ChatThread })
    self.messages = params.messages or {}
    -- FYI think of params as the next request params
    self.params = params or {}
    -- if I want a history of requests I can build that separately
    self.last_request = nil

    self.base_url = base_url
    return self
end

---@param request CurlRequestForThread
function ChatThread:set_last_request(request)
    self.last_request = request
end

---@param message TxChatMessage
function ChatThread:add_message(message)
    -- TODO drop previous messages => message.reasoning_content once a final message is detected?
    if not message.role then
        error("message.role is required")
    end
    table.insert(self.messages, message)
end

---@return table body
function ChatThread:next_curl_request_body()
    -- TODO add support for FimReasoningLevel.off => do the same as I am doing in FIM by setting last message w/ role==assistant and the message can prefill to force no thinking
    --   TODO see this in fim code:
    --     local fixed_thoughts = HarmonyFimPromptBuilder.deep_thoughts_about_fim

    ---@param array any[]
    ---@return any[]
    function clone_array_container_not_items(array)
        local copy = {}
        for i = 1, #array do
            copy[i] = array[i]
        end
        return copy
    end

    local body = {
        -- FYI keep in mind the messages you send DO not mirror the ones you've received...
        --  each turn adds one assistant response message and then you feed in a user message (follow up)...
        --    but if you send prefill assistant message... you'll want to discard that in your response messages (if it were kept somehow, not sure it is, cannot quite recall)
        --      you only want to collect the synthetic, rendered assistant message into ONE new assistant message
        --        could be analysis + final
        --        could be analysis + tool call
        --        thse are the two likely paths right now
        --        you can prefill that analysis
        --        you can actually prefill bogus messages too!
        messages = clone_array_container_not_items(self.messages)
    }
    -- PRN keep/drop thinking myself? btw clone messages before changing them
    -- merge params onto root of body:
    for k, v in pairs(self.params) do
        body[k] = v
    end
    return body
end

function ChatThread:dump()
    -- log:luaify_trace("last_request's RxAccumulatedMessages", self.last_request.accumulated_model_response_messages)
    -- log:luaify_trace("thread's TxChatMessages (history, sent on followup/toolresults)", self.messages)
    log:luaify_trace("ChatThread:dump", self)
end

return ChatThread
