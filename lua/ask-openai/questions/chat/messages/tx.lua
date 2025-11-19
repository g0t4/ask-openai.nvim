local log = require('ask-openai.logs.logger').predictions()
local ansi = require('ask-openai.prediction.ansi')

---@class TxChatMessage : OpenAIChatCompletion_TxChatMessage
---@field reasoning_content? string TODO isn't this "thinking"?
local TxChatMessage = {}

---@enum TX_MESSAGE_ROLES
local TX_MESSAGE_ROLES = {
    USER = "user",
    ASSISTANT = "assistant",
    TOOL = "tool", -- FYI this is for TOOL RESULTS
    SYSTEM = "system",
}

-- TODO! I want end to end testing to verify scenarios that go into the model (the actual prompt) based on TxChatMessage inputs
--  TxChatMessage inputs => .__verbose.prompt output
--  will require --verbose-prompt arg to llama-server
--  VERIFY |tojson fix for tool results, AND tool call args
--  VERIFY other fixes identified by unsloth:
--     https://unsloth.ai/blog/gpt-oss
--     icdiff https://huggingface.co/openai/gpt-oss-120b/raw/main/chat_template.jinja https://huggingface.co/unsloth/gpt-oss-120b/raw/main/chat_template.jinja

---@param role TX_MESSAGE_ROLES
---@param content string
---@return TxChatMessage
function TxChatMessage:new(role, content)
    self = setmetatable({}, { __index = TxChatMessage })
    self.role = role
    self.content = content
    return self
end

---@param tool_call ToolCall
---@return OpenAIChatCompletion_ToolResult_TxChatMessage
function TxChatMessage:tool_result(tool_call)
    -- FYI see NOTES.md for "fix" => removed `|tojson` from jinja template for message.content

    -- * required: role, content, tool_call_id - docs https://platform.openai.com/docs/api-reference/chat/create#chat_create-messages-tool_message
    local content = vim.json.encode(tool_call.call_output.result)
    self = TxChatMessage:new(TX_MESSAGE_ROLES.TOOL, content) --[[@as OpenAIChatCompletion_ToolResult_TxChatMessage]]

    self.tool_call_id = tool_call.id
    -- FTR gptoss/harmony jinja doesn't use tool_call_id b/c no parallel tool calls, it correlates on last tool call's name
    -- DO NOT remove this, other models have parallel tool calling

    -- heads up you might see examples that include function.name, that's not needed with newer tool calling API (b/c tool_call_id does linking now)
    return self
end

---@param content string
---@return OpenAIChatCompletion_System_TxChatMessage
function TxChatMessage:system(content)
    -- * content, role, name - https://platform.openai.com/docs/api-reference/chat/create#chat_create-messages-system_message
    return TxChatMessage:new(TX_MESSAGE_ROLES.SYSTEM, content) --[[@as OpenAIChatCompletion_System_TxChatMessage]]
end

---@param content string
---@return OpenAIChatCompletion_User_TxChatMessage
function TxChatMessage:user(content)
    -- * content, role, name - https://platform.openai.com/docs/api-reference/chat/create#chat_create-messages-user_message
    return TxChatMessage:new(TX_MESSAGE_ROLES.USER, content) --[[@as OpenAIChatCompletion_User_TxChatMessage]]
end

--- differentiate TxChatMessage usage by making explicit this provides context to another user request
---@param content string
---@return OpenAIChatCompletion_User_TxChatMessage
function TxChatMessage:user_context(content)
    -- FYI it would be fine to remove this after my RxAccumulatedMessage refactor
    return TxChatMessage:user(content)
end

---@param rx_message RxAccumulatedMessage
---@return OpenAIChatCompletion_Assistant_TxChatMessage
function TxChatMessage:from_assistant_rx_message(rx_message)
    -- docs: https://platform.openai.com/docs/api-reference/chat/create#chat_create-messages-assistant_message
    -- * content, role, name, tool_calls ...  also: refusal, audio (not using these)
    --   NO mention of sending thinking back! so, no OpenAI compat name for that!

    -- MAP the assistant's RxAccumulatedMessage message to TxChatMessage

    local tx_message = TxChatMessage:new(rx_message.role, rx_message.content) --[[@as OpenAIChatCompletion_Assistant_TxChatMessage]]
    tx_message.name = rx_message.name -- optional, I am not using this on the rx_message incoming side

    -- TODO! map thinking content (and let llama-server's jinja drop the thinking once no longer relevant) ?
    --  or double back at some point and drop it explicitly (too and/or instead)?
    -- tx_message.thinking = message.reasoning_content
    -- FYI gptoss jinja => assistant_message.(thinking|content) == return/resume CoT thinking after/between tool calls
    --    FYI qwen3 uses reasoning_content (UGH)

    --- * map tool calls
    if rx_message.tool_calls then
        tx_message.tool_calls = {} -- only set if assisant type message
        for _, call_request in ipairs(rx_message.tool_calls) do
            -- FYI embed function here so no confusion about what is using it
            -- only clone needed fields
            -- * function.arguments, function.name, id, type docs: https://platform.openai.com/docs/api-reference/chat/create#chat_create-messages-assistant_message-tool_calls
            ---@type OpenAIChatCompletion_Assistant_TxChatMessage_ToolCallRequest
            local new_call = {
                id = call_request.id,
                -- index = call_request.index, -- not in OpenAI docs... I think this is just per request/response anyways
                type = call_request.type,
                ["function"] = {
                    name = call_request["function"].name,
                    arguments = call_request["function"].arguments,
                }
            }
            table.insert(tx_message.tool_calls, new_call)
        end
    end

    return tx_message
end

return TxChatMessage
