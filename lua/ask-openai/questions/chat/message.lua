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

function ChatMessage:new_tool_response(call_result_object_not_json, tool_call_id, name)
    -- TODO if I keep using this bullshit /v1/chat/completions messages format that is OSTENSIBLY UNIVERSAL...
    --   TODO I need tm have tests in place to verify vs .__verbose.prompt that I know what is going on b/c goddamn

    --  FYI llama-server uses the gptoss jinja template w/ tojson (other models had similar part in their tool calling)
    --   SO DO NOT ENCODE to JSON... else it ends up double encoded
    --   SEE tojson in template:
    --     https://github.com/ggml-org/llama.cpp/blob/cb623de3f/models/templates/openai-gpt-oss-120b.jinja#L322
    --   FYI use --verbose-prompt => logs (IIRC also final SSE) => __verbose.prompt has rendered prompt
    --   ALSO harmony spec on raw JSON inputs:
    --     https://cookbook.openai.com/articles/openai-harmony#receiving-tool-calls
    --
    -- self = ChatMessage:new("tool", call_result_object_not_json) -- blocked by server, this is needed
    self = ChatMessage:new("tool", vim.json.encode(call_result_object_not_json)) -- this works but it is why I have issues I think ... works but results in double encoded in prompt (UGH)
    --- FUUUUUUUUUCK llama-server won't allow content to be an object... yet ;)
    ---   llama-server is rejecting raw objects?! only allows strings/arrays...
    ---   WHAT THE LITERAL FUCK MAN
    ---   https://github.com/ggml-org/llama.cpp/blob/cb623de3f/tools/server/utils.hpp#L611-L614
    ---   I suppose I could just wrap my result in an array... NOPE THAT IS BLOCKED TOO
    ---   I'll go get rid of the runtime check :)
    --- FYI! modified server template to drop |tojson and that works now (clean/raw JSON in harmony format!)
    ---    I can use this for now
    ---
    -- {%- elif message.role == 'tool' -%}
    --     ...
    --     {{- "<|start|>functions." + last_tool_call.name }}
    --     {{- " to=assistant<|channel|>commentary<|message|>" + message.content|tojson + "<|end|>" }}
    --
    -- FYI my fix:
    --     {{- " to=assistant<|channel|>commentary<|message|>" + message.content + "<|end|>" }}
    ---
    --- !!! WAIT... so I send both the tool_call.arguments message as json encoded and then tool result JSON encoded
    ---     ! THE FORMER tool_call arguments are correct in the rendered prompt (nevermind they have |tojson too!)
    ---       BOTH USE |tojson... so smth differs in the server code!!
    ---       smth about parse_tool_calls may be related, an option... but also that might just be about parsing from model's generated prompt
    ---     is there smth server side that parses the tool_call.arguments into an object first?
    ---     is there a way to do the same for the results?
    ---

    -- TODO! what about tojson on args in original tool call request message (WHEN SENDING IT BACK)?
    -- FYI __verbose.prompt has correct raw JSON for original tool_call request message (when it is sent back to the model)
    -- https://github.com/ggml-org/llama.cpp/blob/cb623de3f/models/templates/openai-gpt-oss-120b.jinja#L298-L299   --
    --   => ? tool_call.arguments|tojson
    -- BTW upon inspection, the returned args seem fine (raw JSON looks good)... BUT HOW?!

    -- PRN enforce strings are not empty?
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

ChatMessage.LIFECYCLE = {
    -- FYI I merged two concepts: message from model + managing requested tool_call object(s)
    -- streaming -> rx finish_reason=stop/length -> finished
    -- streaming -> rx finish_reason=tool_calls -> pending_tool_call -> calling -> rx results -> finished (tool call done)

    STREAMING = "streaming", -- server is sending message (streaming SSEs)
    FINISHED = "finished", -- server is done sending the message

    -- * tool call related
    -- PENDING_TOOL_CALL = "pending_tool_call", -- next the client will call the tool (add this only IF NEEDED)
    TOOL_CALLING = "tool_calling", -- client is calling the tool, waiting for it to complete
    TOOLS_DONE = "tool_called", -- tool finished (next message will send results to server for a new "TURN" in chat history)
}

function ChatMessage:get_lifecycle_step()
    -- TODO try using this to simplify consumer logic... i.e. in streaming chat window  message/tool formatters/summarizers
    if self:is_still_streaming() then
        return ChatMessage.LIFECYCLE.STREAMING
    end
    local finish_reason = self:get_finish_reason()
    if finish_reason == ChatMessage.FINISH_REASONS.TOOL_CALLS then
        -- IIRC tool_calls are parsed before FINISHED state... so just check all are complete (or not)
        for _, call in ipairs(self.tool_calls) do
            if not call:is_done() then
                return ChatMessage.LIFECYCLE.TOOL_CALLING
            end
        end
    end
    return ChatMessage.LIFECYCLE.FINISHED
end

return ChatMessage
