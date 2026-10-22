local log = require('devtools.logs.logger').universal()
local ansi = require('devtools.ansi')
local plumbing = require('ask-openai.tools.plumbing')

---@class TxChatMessage : OpenAIChatCompletion_TxChatMessage
local TxChatMessage = {}

---@enum TX_MESSAGE_ROLES
local TX_MESSAGE_ROLES = {
    USER = "user",
    ASSISTANT = "assistant",
    TOOL = "tool", -- FYI this is for TOOL RESULTS
    SYSTEM = "system",
    DEVELOPER = "developer",
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
---@return TxChatMessage? image_message
function TxChatMessage:tool_result(tool_call)
    -- FYI see NOTES.md for "fix" => removed `|tojson` from jinja template for message.content

    -- * required: role, content, tool_call_id - docs https://platform.openai.com/docs/api-reference/chat/create#chat_create-messages-tool_message
    -- * Unwrap the MCP result into plain text so the model sees raw output
    --   instead of a JSON string wrapping JSON-escaped text (JSON-in-JSON).
    local content, image_urls = plumbing.tool_result_content(tool_call.call_output.result)

    -- vLLM's DeepSeek template drops image placeholders in tool messages.
    -- Return a separate user message; the frontend adds it after all tool replies.
    local image_message
    if #image_urls > 0 then
        local name = tool_call["function"] and tool_call["function"].name or "tool"
        local content_blocks = { { type = "text", text = "Images returned by " .. name .. " (tool_call_id: " .. tool_call.id .. ")." } }
        for _, url in ipairs(image_urls) do
            content_blocks[#content_blocks + 1] = { type = "image_url", image_url = { url = url } }
        end
        image_message = TxChatMessage:user(content_blocks)
    end

    self = TxChatMessage:new(TX_MESSAGE_ROLES.TOOL, content) --[[@as OpenAIChatCompletion_ToolResult_TxChatMessage]]

    self.tool_call_id = tool_call.id
    -- FTR gptoss/harmony jinja doesn't use tool_call_id b/c no parallel tool calls, it correlates on last tool call's name
    -- DO NOT remove this, other models have parallel tool calling

    -- heads up you might see examples that include function.name, that's not needed with newer tool calling API (b/c tool_call_id does linking now)

    -- * attach timing metadata (ignored by backend, logged with trace)
    if tool_call.call_output and tool_call.call_output.duration_ms then
        self.duration_ms = tool_call.call_output.duration_ms
    end
    if tool_call.call_output and tool_call.call_output.start_time_ms then
        self.start_time_ms = tool_call.call_output.start_time_ms
    end

    -- copy over tool call progress notifications for capturing to trace file? or go with sub traces in a given MCP server?
    -- PRN add a way to strip these when sending to server? does it matter?
    self.progress_notifications = tool_call.progress_notifications

    return self, image_message
end

---@param tool_call_id string
---@param content string
---@param notification? table -- optional MCP notification (e.g. background/done) carried for chat viewer rendering
---@return OpenAIChatCompletion_ToolResult_TxChatMessage
function TxChatMessage:tool_completion(tool_call_id, content, notification)
    -- FYI like tool_result() this is a role="tool" message, but it is NOT a direct
    -- It's an async completion notice injected after the agent's turn so the model
    -- knows to call process_status. gptoss/llama-server correlates on the last tool
    -- call name and tolerates this; strict OpenAI backends may not.
    self = TxChatMessage:new(TX_MESSAGE_ROLES.TOOL, content) --[[@as OpenAIChatCompletion_ToolResult_TxChatMessage]]
    self.tool_call_id = tool_call_id
    -- * carry the source notification for chat viewer rendering (like duration_ms
    --   metadata, it rides along on the message; the content already carries the data)
    self.notification = notification
    return self
end

---@param content string
---@return TxChatMessage
function TxChatMessage:system(content)
    -- * content, role, name - https://platform.openai.com/docs/api-reference/chat/create#chat_create-messages-system_message
    return TxChatMessage:new(TX_MESSAGE_ROLES.SYSTEM, content)
end

---@param content string
---@return TxChatMessage
function TxChatMessage:user(content)
    -- * content, role, name - https://platform.openai.com/docs/api-reference/chat/create#chat_create-messages-user_message
    return TxChatMessage:new(TX_MESSAGE_ROLES.USER, content)
end

--- differentiate TxChatMessage usage by making explicit this provides context to another user request
---@param content string
---@return TxChatMessage
function TxChatMessage:user_context(content)
    return TxChatMessage:user(content)
end

---@param content string
---@return OpenAIChatCompletion_Assistant_TxChatMessage
function TxChatMessage:assistant(content)
    return TxChatMessage:new(TX_MESSAGE_ROLES.ASSISTANT, content) --[[@as OpenAIChatCompletion_Assistant_TxChatMessage]]
end

---@param rx_message RxAccumulatedMessage
---@return OpenAIChatCompletion_Assistant_TxChatMessage
function TxChatMessage:from_assistant_rx_message(rx_message)
    -- docs: https://platform.openai.com/docs/api-reference/chat/create#chat_create-messages-assistant_message
    -- * content, role, name, tool_calls ...  also: refusal, audio (not using these)
    --   NO mention of sending thinking back! so, no OpenAI compat name for that!

    -- Safety net: default role to "assistant" if rx_message.role is missing
    local role = rx_message.role or "assistant"
    local tx_message = TxChatMessage:new(role, rx_message.content) --[[@as Ask_OpenAIChatCompletion_Assistant_TxChatMessage]]

    -- Preserve raw statistics alongside assistant history for trace viewers.
    if rx_message.last_sse then
        require("ask-openai.backends.response_metadata").copy(rx_message.last_sse, tx_message)
    end

    -- FYI qwen3-8b's template exploded after tool call w/ reasoning_content included: (smth about lstrip).. if I comment out next line, then it works fine (tool calls and all):
    tx_message.reasoning_content = rx_message.reasoning_content
    -- FYI llama-server populates message.thinking via message.reasoning_content (for gptoss):
    --   https://github.com/ggml-org/llama.cpp/blob/0de8878c9/common/chat.cpp#L1813-L1817
    -- TODO modify trace:add_message() to drop reasoning_content when final message is added

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

---@return boolean
function TxChatMessage:is_gptoss_assistant_turn_final_message()
    -- FYI if you miss flagging a final message, gptoss jinja template will ignore it anyways

    -- FYI jinja template has criteria to detect final:
    --   https://github.com/ggml-org/llama.cpp/blob/0de8878c9/models/templates/openai-gpt-oss-120b.jinja#L277-L282
    --   assistant + no tool_calls ... exactly what I dervied on my own!
    --
    --   WHY b/c there are only two types of Assistant messages:
    --     tool_call request (w/ reasoning/content is possible, or w/o)
    --     final response (w/ either reasoning or content but doesn't matter which, and even if neither, is still a final message)

    local is_assistant = self.role == TX_MESSAGE_ROLES.ASSISTANT

    ---@cast self OpenAIChatCompletion_Assistant_TxChatMessage
    local no_tool_calls = (self.tool_calls == nil or #self.tool_calls == 0)

    return is_assistant and no_tool_calls
end

return TxChatMessage
