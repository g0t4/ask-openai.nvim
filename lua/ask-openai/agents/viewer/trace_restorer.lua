local log = require("ask-openai.logs.logger").predictions()
local HLGroups = require("ask-openai.hlgroups")
local Fold = require("ask-openai.agents.viewer.fold")
local LinesBuilder = require("ask-openai.agents.viewer.lines_builder")
local formatters = require("ask-openai.agents.viewer.formatters")
local ToolCallOutput = require("ask-openai.agents.tools.tool_call_output")
local safely = require("ask-openai.helpers.safely")

local M = {}

--- List all entries in a directory using uv.fs_opendir.
---
---@param dir_path string
---@return table[] entries -- array of {name, type} tables
local function list_directory_entries(dir_path)
    local dir = vim.uv.fs_opendir(dir_path, nil, 100)
    if not dir then
        return {}
    end

    local entries = {}
    local has_more = true

    while has_more do
        local batch = vim.uv.fs_readdir(dir)
        if not batch then
            break
        end

        for _, entry in ipairs(batch) do
            table.insert(entries, entry)
        end

        has_more = #batch > 0
    end

    vim.uv.fs_closedir(dir)
    return entries
end

--- Resolve a session identifier to an absolute file path for the trace JSON.
---
---@param session_id string|nil -- unix timestamp or *-trace.json filename, or nil for most recent
---@return string? file_path -- nil if not found
function M.resolve_trace_path(session_id)
    local state_dir = vim.fn.stdpath("state") .. "/ask-openai/agents"

    -- * no session_id => find most recent trace
    if not session_id or session_id == "" then
        local entries = list_directory_entries(state_dir)
        if #entries == 0 then
            log:warn("No trace files found in: " .. state_dir)
            return nil
        end

        -- Sort by filename descending (timestamps are numeric, so lexicographic sort works)
        table.sort(entries, function(a, b)
            return a.name > b.name
        end)

        for _, entry in ipairs(entries) do
            if entry.type == "file" and entry.name:match("-trace.json$") then
                return state_dir .. "/" .. entry.name
            end
        end

        log:warn("No *-trace.json files found in: " .. state_dir)
        return nil
    end

    -- * session_id might be just a timestamp (e.g. "1781384705") or a full filename ("1781384705-trace.json")
    local trace_filename = session_id
    if not session_id:match("-trace.json$") then
        trace_filename = session_id .. "-trace.json"
    end

    local full_path = state_dir .. "/" .. trace_filename
    if vim.fn.filereadable(full_path) == 1 then
        return full_path
    end

    log:error("Trace file not found: " .. full_path)
    return nil
end

--- Load and parse a trace JSON file.
---
---@param file_path string
---@return table|nil trace_data -- the decoded JSON table, or nil on failure
function M.load_trace(file_path)
    local json_text = require("ask-openai.helpers.files").read_text(file_path)
    if not json_text then
        return nil
    end

    local ok, data = pcall(vim.json.decode, json_text)
    if not ok then
        log:error("Failed to decode trace JSON from: " .. file_path)
        return nil
    end

    return data
end

--- Extract messages array from a trace data table.
--- Handles both the current format (request_body.messages) and potential future formats.
---
---@param trace_data table
---@return table[] messages -- array of message tables with role, content, etc.
function M.extract_messages(trace_data)
    if trace_data.request_body and trace_data.request_body.messages then
        return trace_data.request_body.messages
    end

    -- Fallback: look for messages at top level
    if trace_data.messages then
        return trace_data.messages
    end

    log:error("Trace data has no messages array")
    return {}
end

--- Build a lookup table from tool_call_id to tool result message content.
--- This allows us to match assistant tool calls with their corresponding results.
---
---@param messages table[] -- array of message tables
---@return table<string, string> tool_results_by_id
local function build_tool_results_map(messages)
    local results = {}
    for _, msg in ipairs(messages) do
        if msg.role == "tool" and msg.tool_call_id then
            results[msg.tool_call_id] = msg.content or ""
        end
    end
    return results
end

--- Construct a synthetic ToolCallOutput from a tool result message content string.
--- The content is typically MCP-style JSON: {"content": [{"name": "STDOUT", "text": "...", "type": "text"}]}
---
---@param content string -- raw JSON string from the tool result message
---@return ToolCallOutput?
local function build_tool_call_output(content)
    if not content or content == "" then
        return nil
    end

    local ok, decoded = safely.decode_json(content)
    if not ok or type(decoded) ~= "table" then
        log:warn("Failed to decode tool result JSON: " .. content:sub(1, 80))
        return nil
    end

    -- Check for MCP-style output with .content array
    if decoded.content and type(decoded.content) == "table" then
        -- Check for error indicator
        local is_error = false
        if decoded.isError then
            is_error = true
        elseif type(decoded.error) ~= "nil" then
            is_error = true
        end

        return ToolCallOutput:new({
            result = {
                content = decoded.content,
                isError = is_error,
            },
        })
    end

    -- Fallback: treat the whole decoded table as the result
    return ToolCallOutput:new({
        result = decoded,
        isError = false,
    })
end

--- Construct a synthetic ToolCall object from trace data.
--- The formatters expect ToolCall objects with specific fields and methods.
---
---@param tool_call_data table -- raw tool call data from trace (with function.name, function.arguments, id)
---@param tool_results_by_id table<string, string> -- lookup from tool_call_id to result content
---@return table synthetic_tool_call
local function build_synthetic_tool_call(tool_call_data, tool_results_by_id)
    local func = tool_call_data["function"] or {}
    local call_id = tool_call_data.id or ""

    -- Build call_output from matched tool result
    local call_output = nil
    local result_content = tool_results_by_id[call_id]
    if result_content then
        call_output = build_tool_call_output(result_content)
    end

    -- Construct a synthetic ToolCall that satisfies formatter expectations.
    -- The is_done method must be a proper function on the table (not via metatable)
    -- because formatters call it with : syntax which passes self as first arg.
    local has_call_output = call_output ~= nil

    return {
        id = call_id,
        type = tool_call_data.type or "function",
        index = tool_call_data.index or 0,
        ["function"] = {
            name = func.name or "unknown",
            arguments = func.arguments or "",
        },
        call_output = call_output,
        progress_notifications = {},
        start_time_ms = 0,
        is_done = function()
            return has_call_output
        end,
    }
end

--- Create a minimal synthetic message wrapper that satisfies formatter expectations.
--- Formatters call message:is_still_streaming() and message:is_done_streaming().
--- For restored traces, we always return "done" values.
---
---@return table synthetic_message
local function build_synthetic_message()
    return {
        is_still_streaming = function()
            return false
        end,
        is_done_streaming = function()
            return true
        end,
    }
end

--- Find the index (1-based) of the first assistant message in the messages array.
--- Returns nil if no assistant message exists.
---
---@param messages table[]
---@return integer|nil first_assistant_index
local function find_first_assistant_message_index(messages)
    for idx, msg in ipairs(messages) do
        if msg.role == "assistant" then
            return idx
        end
    end
    return nil
end

--- Find the index (1-based) of the last user/developer message before first_assistant_index.
--- Returns nil if no such message exists.
---
---@param messages table[]
---@param first_assistant_index integer|nil
---@return integer|nil last_user_before_first_assistant
local function find_last_user_before_first_assistant(messages, first_assistant_index)
    if not first_assistant_index then
        return nil
    end

    -- Search backwards from just before the first assistant
    for idx = first_assistant_index - 1, 1, -1 do
        local role = messages[idx].role
        if role == "user" or role == "developer" then
            return idx
        end
        -- Stop if we hit another assistant (shouldn't happen before first_assistant_index)
        if role == "assistant" then
            break
        end
    end

    return nil
end

--- Render a single message from the trace into the LinesBuilder.
--- Handles system, user, assistant (with reasoning + tool calls), and tool result messages.
---
---@param lines LinesBuilder
---@param msg table -- message table from trace
---@param tool_results_by_id table<string, string>
---@param should_fold_content boolean -- if true, fold the content; if false, show unfolded
local function render_message(lines, msg, tool_results_by_id, should_fold_content)
    local role = msg.role or "unknown"

    -- * system messages: always folded (ancillary context)
    if role == "system" then
        lines:mark_next_line(HLGroups.SYSTEM_PROMPT)
        lines:append_folded_styled_text("system\n" .. (msg.content or ""), "")
        return
    end

    -- * developer messages: always folded (ancillary context)
    if role == "developer" then
        lines:mark_next_line(HLGroups.SYSTEM_PROMPT)
        lines:append_folded_styled_text("developer\n" .. (msg.content or ""), "")
        return
    end

    -- * user messages: show role header + content
    if role == "user" then
        lines:append_role_header("user")
        if should_fold_content then
            lines:append_folded_styled_text(msg.content or "", "")
        else
            lines:append_text(msg.content or "")
        end
        lines:append_blank_line()
        return
    end

    -- * assistant messages: show reasoning (if any) + content + tool calls
    if role == "assistant" then
        lines:append_role_header("assistant")

        local reasoning_content = msg.reasoning_content or ""
        local content = msg.content or ""
        local tool_calls = msg.tool_calls or {}

        -- Only add role header content if there's something to show
        if reasoning_content ~= "" or content ~= "" or #tool_calls > 0 then
            lines:append_folded_styled_text(reasoning_content, HLGroups.CHAT_REASONING)
            lines:append_text(content)

            for _, tool_call_data in ipairs(tool_calls) do
                local synthetic_tool_call = build_synthetic_tool_call(tool_call_data, tool_results_by_id)
                local function_name = synthetic_tool_call["function"].name or ""
                local formatter = formatters.get_formatter(function_name)

                local ok, err = pcall(function()
                    local synth_msg = build_synthetic_message()
                    formatter(lines, synthetic_tool_call, synth_msg)
                end)
                if not ok then
                    lines:append_unexpected_text("Formatter error: " .. tostring(err))
                    lines:append_text(vim.inspect(tool_call_data))
                end
                lines:append_blank_line_if_last_is_not_blank()
            end
        else
            -- Empty assistant response (edge case)
            lines:append_text("[unexpected: empty response]")
            lines:append_blank_line()
        end

        return
    end

    -- * tool result messages: these are typically not shown directly in the chat viewer
    --   because they are rendered inline with their corresponding tool call above.
    --   Skip them to avoid duplication.
    if role == "tool" then
        return
    end

    -- * unknown roles: show raw
    lines:append_role_header(role)
    lines:append_text(msg.content or "")
    lines:append_blank_line()
end

--- Apply marks and folds from a LinesBuilder to the chat buffer.
--- This is the missing piece that was only done by BufferController during real-time rendering.
---
---@param bufnr number
---@param ns_id number
---@param lines LinesBuilder
local function apply_marks_and_folds(bufnr, ns_id, lines)
    local marks = lines.marks or {}
    if #marks == 0 then
        return
    end

    -- * clear any prior folds on this buffer (from previous restore)
    local chat_window = require("ask-openai.agents.frontend").chat_window
    if chat_window and chat_window.buffer then
        chat_window.buffer.folds = {}
    end

    -- Apply marks/extmarks and build fold ranges
    for _, mark in ipairs(marks) do
        vim.api.nvim_buf_set_extmark(bufnr, ns_id,
            mark.start_line_base0,
            mark.start_col_base0,
            {
                hl_group = mark.hl_group,
                end_line = mark.end_line_base0,
                end_col = mark.end_col_base0,
            }
        )

        -- If this mark has fold=true, create a Fold object and add it to the buffer's folds array
        if mark.fold then
            local fold_start_line_base1 = mark.start_line_base0 + 1
            local fold_end_line_base1 = mark.end_line_base0
            local fold = Fold:new(fold_start_line_base1, fold_end_line_base1)

            if chat_window and chat_window.buffer then
                table.insert(chat_window.buffer.folds, fold)
            end
        end
    end
end

--- Convert raw trace messages (from JSON) to TxChatMessage objects.
--- This is needed because the trace file contains raw message tables,
--- but AgentTrace.messages expects TxChatMessage instances for follow-up.
---
---@param messages table[] -- raw message tables from trace
---@return table tx_messages -- array of TxChatMessage objects
local function convert_trace_messages_to_tx_messages(messages)
    local TxChatMessage = require("ask-openai.agents.messages.tx")
    local tx_messages = {}

    for _, msg in ipairs(messages) do
        local role = msg.role or "unknown"

        if role == "system" then
            table.insert(tx_messages, TxChatMessage:system(msg.content or ""))

        elseif role == "user" then
            table.insert(tx_messages, TxChatMessage:user(msg.content or ""))

        elseif role == "assistant" then
            -- Construct a TxChatMessage for assistant with reasoning and tool_calls
            local tx_msg = TxChatMessage:new("assistant", msg.content or "")
            tx_msg.reasoning_content = msg.reasoning_content or ""

            if msg.tool_calls and #msg.tool_calls > 0 then
                tx_msg.tool_calls = {}
                for _, tc in ipairs(msg.tool_calls) do
                    local func = tc["function"] or {}
                    table.insert(tx_msg.tool_calls, {
                        id = tc.id or "",
                        type = tc.type or "function",
                        ["function"] = {
                            name = func.name or "",
                            arguments = func.arguments or "",
                        }
                    })
                end
            end

            -- Copy timings if present
            if msg.timings then
                tx_msg.timings = msg.timings
            end

            table.insert(tx_messages, tx_msg)

        elseif role == "tool" then
            -- Construct a TxChatMessage:tool_result from the tool_call_id and content
            local tool_call_id = msg.tool_call_id or ""
            local result_content = msg.content or ""

            -- Parse the result content (typically MCP-style JSON)
            local ok, decoded = pcall(vim.json.decode, result_content)
            if not ok or type(decoded) ~= "table" then
                decoded = { content = {} }
            end

            -- Create a synthetic ToolCall object that TxChatMessage:tool_result expects
            local synthetic_tool_call = {
                id = tool_call_id,
                call_output = {
                    result = decoded,
                    isError = decoded.isError or false,
                },
            }

            table.insert(tx_messages, TxChatMessage:tool_result(synthetic_tool_call))

        else
            -- Unknown role, just add as user message
            table.insert(tx_messages, TxChatMessage:user(msg.content or ""))
        end
    end

    return tx_messages
end

--- Build current request params for a follow-up after trace restore.
--- Uses current model/tools settings (not from the original trace).
---
---@return table params -- request body params similar to a fresh request
local function build_followup_params()
    local api = require("ask-openai.api")
    local config = require("ask-openai.config")
    local tool_router = require("ask-openai.tools.router")

    local model_name = api.get_agents_model()
    local base_url = config.get_base_url(model_name)

    -- Build tool definitions (same as a fresh request)
    local tool_definitions, _ = tool_router.openai_tools(false)

    -- Build params similar to ask_agent_command but without system message
    local params = {
        model = "",  -- irrelevant for llama-server
        verbose = true,
    }

    if #tool_definitions > 0 then
        params.tools = tool_definitions
    end

    return params, base_url
end

--- Set up AgentsFrontend for follow-up mode after restoring a trace.
--- Converts trace messages to TxChatMessage objects and creates an AgentTrace
--- instance with current model/tools params (not from the original trace).
---
---@param tx_messages table[] -- TxChatMessage objects from converted trace messages
local function setup_trace_for_followup(tx_messages)
    local AgentTrace = require("ask-openai.agents.trace")
    local AgentsFrontend = require("ask-openai.agents.frontend")

    -- Build current params (fresh, not from original trace)
    local params, base_url = build_followup_params()

    -- Create AgentTrace with old messages + current params
    local new_trace = AgentTrace:new(params, base_url)
    new_trace.messages = tx_messages

    -- Set up AgentsFrontend for follow-up mode
    AgentsFrontend.trace = new_trace

    -- Mark the agent as running (for spinner)
    AgentsFrontend.chat_window:mark_agent_running(true)
    AgentsFrontend.chat_window:ensure_spinner_running("ready")

    -- Show user role hint for follow-up
    AgentsFrontend.show_user_role_as_follow_up_hint()

    -- Set the offset for where streaming messages will be drawn
    AgentsFrontend.this_turn_chat_start_line_base0 = AgentsFrontend.chat_window.buffer:get_line_count() - 1

    log:info("Trace restored and ready for follow-up with " .. #tx_messages .. " messages")
end

--- Render all messages from a trace file into the chat viewer window.
--- Clears the window first, then draws each message using the same formatters
--- as real-time display (but with final/full message state).
---
--- Fold strategy for initial messages (before first assistant):
---   - All system/developer/user messages are folded individually
---   - Exception: the very last user/developer message before the first assistant
---     is shown unfolded (this is the actual prompt that triggered the response)
---
---@param trace_path string -- path to the trace JSON file
---@return boolean success
function M.restore_session(trace_path)
    local trace_data = M.load_trace(trace_path)
    if not trace_data then
        log:error("Failed to load trace: " .. trace_path)
        return false
    end

    local messages = M.extract_messages(trace_data)
    if #messages == 0 then
        log:error("No messages found in trace: " .. trace_path)
        return false
    end

    -- * build tool result lookup before rendering
    local tool_results_by_id = build_tool_results_map(messages)

    -- * find the first assistant message index (determines fold strategy)
    local first_assistant_index = find_first_assistant_message_index(messages)

    -- * find the last user/developer message before first assistant (unfold this one)
    local unfold_user_index = find_last_user_before_first_assistant(messages, first_assistant_index)

    -- * ensure chat window is open
    local AgentsFrontend = require("ask-openai.agents.frontend")
    AgentsFrontend.ensure_chat_window_is_open()

    -- * clear the window
    AgentsFrontend.chat_window:clear()

    -- * create namespace for this render pass
    local ns_id = vim.api.nvim_create_namespace("Ask.TraceRestore." .. tostring(os.time()))

    -- * build lines
    local lines = LinesBuilder:new(ns_id)

    -- Render each message with appropriate folding
    for idx, msg in ipairs(messages) do
        local role = msg.role or "unknown"

        -- Determine if this message should be folded
        local should_fold_content = true

        -- User/developer messages before the first assistant are folded, except the last one
        if idx < first_assistant_index and (role == "user" or role == "developer") then
            should_fold_content = (idx ~= unfold_user_index)
        end

        render_message(lines, msg, tool_results_by_id, should_fold_content)
    end

    -- * convert trace messages to TxChatMessage objects for follow-up
    local tx_messages = convert_trace_messages_to_tx_messages(messages)

    -- * apply to buffer
    vim.schedule(function()
        if not AgentsFrontend.chat_window or not AgentsFrontend.chat_window.buffer_number then
            log:error("Chat window invalidated during restore")
            return
        end

        local bufnr = AgentsFrontend.chat_window.buffer_number
        local with_lines = lines.turn_lines

        -- Clear buffer and set lines
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, with_lines)

        -- Apply marks AND folds (this was the missing piece!)
        apply_marks_and_folds(bufnr, ns_id, lines)

        -- Scroll to top (user can scroll down)
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        -- * set up trace for follow-up mode
        setup_trace_for_followup(tx_messages)

        log:info("Restored " .. #messages .. " messages from trace: " .. trace_path)
    end)

    return true
end

return M
