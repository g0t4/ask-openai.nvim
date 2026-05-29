local log = require('ask-openai.logs.logger').predictions()
local files = require('ask-openai.helpers.files')
local llama_server_client = require('ask-openai.backends.llama_cpp.llama_server_client')
local messages = require("devtools.messages")
local config = require("ask-openai.config")

--- see https://platform.openai.com/docs/api-reference/chat/create
---@class AgentTrace
---@field messages TxChatMessage[]
---@field params ChatParams
---@field last_request CurlRequestForTrace
---@field base_url string
---@field summary string
local AgentTrace = {}

---@param params ChatParams
---@param base_url string
---@return AgentTrace
function AgentTrace:new(params, base_url)
    self = setmetatable({}, { __index = AgentTrace })
    self.messages = params.messages or {}
    -- FYI think of params as the next request params
    self.params = params or {}
    -- if I want a history of requests I can build that separately
    self.last_request = nil
    self.start_time = os.time() -- use as identifier for grouping and writing to disk
    self.base_url = base_url
    self.summary = ""
    return self
end

---@param request CurlRequestForTrace
function AgentTrace:set_last_request(request)
    self.last_request = request
end

---@param message TxChatMessage
function AgentTrace:add_message(message)
    if not message.role then
        -- TODO do I really want to blow up here?
        error("message.role is missing")
        log:error("message.role is missing", vim.inspect(message))
    end
    table.insert(self.messages, message)
end

---@return table body
function AgentTrace:next_curl_request_body()
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

--- Calls the LLM to generate a summary of this trace.
--- Zeros out `summary` before making the request, then sets the response on completion.
function AgentTrace:create_summary()

    local trace_json = vim.json.encode(self.messages)

    local body = {
        messages = {
            {
                role = "system",
                content =
                [[Given a serialized AgentTrace (containing messages, params, and request metadata), provide a concise one‑sentence summary of the conversation’s purpose. This summary will be shown to users to pick from a list of threads to resume.]],
            },
            {
                role = "user",
                content = "Summarize this trace:\n" .. trace_json,
            },
        },
    }

    local summarizer_url = config.get_endpoints().summarizer.base_url
    local response = llama_server_client.v1_chat_completions(summarizer_url, body)
    if response and response.body and response.body.choices and response.body.choices[1] then
        self.summary = response.body.choices[1].message.content or ""
    end

    return self
end

function AgentTrace:dump()
    -- log:luaify_trace("last_request's RxAccumulatedMessages", self.last_request.accumulated_model_response_messages)
    -- log:luaify_trace("trace's TxChatMessages (history, sent on followup/toolresults)", self.messages)
    log:luaify_trace("AgentTrace:dump", self)
    messages:ensure_open()
    messages:append(vim.inspect(self))
end

--- Saves the trace data to a JSON file named `test.json` in the current directory.
function AgentTrace:save()
    local json_content = vim.json.encode(self)

    local file_path = "test.json"
    local file_handle = io.open(file_path, "w")
    if not file_handle then
        error("Failed to open file for writing: " .. file_path)
    end

    file_handle:write(json_content)
    file_handle:close()
end

function AgentTrace:load(file)
    local file = "test.json"
    local json = files.read_text(file)
    log:info("json", json)
    if not json then
        return nil
    end
    return vim.json.decode(json)
end

return AgentTrace
