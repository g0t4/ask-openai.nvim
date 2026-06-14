local log = require("ask-openai.logs.logger").predictions()
local HLGroups = require("ask-openai.hlgroups")
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

--- Render a single message from the trace into the LinesBuilder.
--- Handles system, user, assistant (with reasoning + tool calls), and tool result messages.
---
---@param lines LinesBuilder
---@param msg table -- message table from trace
---@param tool_results_by_id table<string, string>
local function render_message(lines, msg, tool_results_by_id)
    local role = msg.role or "unknown"

    -- * system messages: show as system prompt
    if role == "system" then
        lines:mark_next_line(HLGroups.SYSTEM_PROMPT)
        lines:append_folded_styled_text("system\n" .. (msg.content or ""), "")
        return
    end

    -- * user messages: show role header + content
    if role == "user" then
        lines:append_role_header("user")
        lines:append_text(msg.content or "")
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

--- Render all messages from a trace file into the chat viewer window.
--- Clears the window first, then draws each message using the same formatters
--- as real-time display (but with final/full message state).
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

    -- * ensure chat window is open
    local AgentsFrontend = require("ask-openai.agents.frontend")
    AgentsFrontend.ensure_chat_window_is_open()

    -- * clear the window
    AgentsFrontend.chat_window:clear()

    -- * create namespace for this render pass
    local ns_id = vim.api.nvim_create_namespace("Ask.TraceRestore." .. tostring(os.time()))

    -- * build lines
    local lines = LinesBuilder:new(ns_id)

    -- Render each message
    for _, msg in ipairs(messages) do
        render_message(lines, msg, tool_results_by_id)
    end

    -- * apply to buffer
    vim.schedule(function()
        if not AgentsFrontend.chat_window or not AgentsFrontend.chat_window.buffer_number then
            log:error("Chat window invalidated during restore")
            return
        end

        local bufnr = AgentsFrontend.chat_window.buffer_number
        local with_lines = lines.turn_lines
        local marks = lines.marks

        -- Clear buffer and set lines
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, with_lines)

        -- Apply marks/extmarks
        if marks then
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
            end
        end

        -- Scroll to top (user can scroll down)
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        log:info("Restored " .. #messages .. " messages from trace: " .. trace_path)
    end)

    return true
end

return M
