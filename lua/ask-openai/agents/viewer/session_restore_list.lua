local log = require("devtools.logs.logger").universal()
local FloatWindow = require("ask-openai.helpers.float_window")

--- Represents a single trace session entry.
---@class SessionEntry
---@field trace_path string -- absolute path to the -trace.json file
---@field session_id string -- unix timestamp extracted from filename
---@field start_time integer -- unix timestamp of when session started
---@field age_str string -- human-readable age (e.g. "5m", "2h", "3d")
---@field initial_user_message string -- last user/developer message before first assistant

local M = {}

--- Track the current instance to prevent duplicate windows.
--- Similar to AgentsFrontend.chat_window pattern.
---@type SessionRestoreList|nil
M._instance = nil

--- Format a unix timestamp into a human-readable relative age string.
---
---@param timestamp integer -- unix timestamp
---@return string age_str
local function format_age(timestamp)
    local now = os.time()
    local diff = now - timestamp

    if diff < 60 then
        return diff .. "s ago"
    elseif diff < 3600 then
        local minutes = math.floor(diff / 60)
        return minutes .. "m ago"
    elseif diff < 86400 then
        local hours = math.floor(diff / 3600)
        return hours .. "h ago"
    else
        local days = math.floor(diff / 86400)
        return days .. "d ago"
    end
end

--- Truncate a string to a maximum length, adding "..." if truncated.
---
---@param str string
---@param max_len integer
---@return string truncated
local function truncate_string(str, max_len)
    if not str or #str <= max_len then
        return str or ""
    end
    return str:sub(1, max_len - 3) .. "..."
end

--- Extract the initial user message from trace data.
--- The initial user message is defined as the last user/developer message
--- before the first assistant response.
---
---@param messages table[] -- array of message tables
---@return string initial_message
local function extract_initial_user_message(messages)
    local first_assistant_index = nil
    for idx, msg in ipairs(messages) do
        if msg.role == "assistant" then
            first_assistant_index = idx
            break
        end
    end

    if not first_assistant_index then
        return "[no assistant response]"
    end

    -- Search backwards from just before the first assistant
    for idx = first_assistant_index - 1, 1, -1 do
        local role = messages[idx].role
        if role == "user" or role == "developer" then
            local content = messages[idx].content or ""
            return truncate_string(content, 80)
        end
        if role == "assistant" then
            break
        end
    end

    return "[no user prompt found]"
end

--- Load and parse a trace JSON file to extract session metadata.
---
---@param trace_path string -- absolute path to the -trace.json file
---@return SessionEntry|nil entry
local function load_session_entry(trace_path)
    local filename = vim.fn.fnamemodify(trace_path, ":t")

    -- Extract session_id from filename (e.g., "1781384705-trace.json" -> "1781384705")
    local session_id = filename:match("^(%d+)-trace%.json$")
    if not session_id then
        log:warn("Could not extract session_id from filename: " .. filename)
        return nil
    end

    -- Load trace data
    local trace_data = require("ask-openai.agents.viewer.trace_restorer").load_trace(trace_path)
    if not trace_data then
        log:warn("Failed to load trace: " .. trace_path)
        return nil
    end

    local messages = require("ask-openai.agents.viewer.trace_restorer").extract_messages(trace_data)
    if #messages == 0 then
        log:warn("No messages in trace: " .. trace_path)
        return nil
    end

    local start_time = trace_data.start_time or tonumber(session_id) or os.time()

    return {
        trace_path = trace_path,
        session_id = session_id,
        start_time = start_time,
        age_str = format_age(start_time),
        initial_user_message = extract_initial_user_message(messages),
    }
end

--- List all available trace sessions sorted by time (newest first).
---
---@return SessionEntry[] entries
function M.list_sessions()
    local state_dir = vim.fn.stdpath("state") .. "/ask-openai/agents"

    -- Re-implement directory listing here for efficiency (avoid loading each trace twice).
    local dir = vim.uv.fs_opendir(state_dir, nil, 100)
    if not dir then
        log:warn("Could not open state directory: " .. state_dir)
        return {}
    end

    local trace_files = {}
    local has_more = true
    while has_more do
        local batch = vim.uv.fs_readdir(dir)
        if not batch then
            break
        end
        for _, entry in ipairs(batch) do
            if entry.type == "file" and entry.name:match("^%d+-trace%.json$") then
                table.insert(trace_files, entry.name)
            end
        end
        has_more = #batch > 0
    end
    vim.uv.fs_closedir(dir)

    -- Sort descending (newest first)
    table.sort(trace_files, function(a, b)
        return a > b
    end)

    local sessions = {}
    for _, filename in ipairs(trace_files) do
        local trace_path = state_dir .. "/" .. filename
        local entry = load_session_entry(trace_path)
        if entry then
            table.insert(sessions, entry)
        end
    end

    return sessions
end

--- Format a single session entry as display lines for the list window.
---
---@param entry SessionEntry
---@param index integer -- 1-based index in the list
---@return string[] display_lines
local function format_entry_lines(entry, index)
    local header_line = ("[%d] %s (%s)"):format(index, entry.session_id, entry.age_str)

    -- Wrap the initial message in a folded block for compactness
    local message_preview = truncate_string(entry.initial_user_message, 70)
    local folded_content = "└─ " .. message_preview

    return { header_line, folded_content }
end

--- Create and open the session restore list float window.
--- Reuses existing instance if already open.
---
---@return SessionRestoreList|nil instance
function M.open()
    -- * check if instance already exists and is valid
    if M._instance ~= nil then
        local instance = M._instance
        if instance.win_id and vim.api.nvim_win_is_valid(instance.win_id) then
            -- Window is already open, just bring it to focus
            vim.api.nvim_set_current_win(instance.win_id)
            return instance
        end
        -- Window was closed but buffer still exists; clean up old instance
        if instance.buffer_number and vim.api.nvim_buf_is_valid(instance.buffer_number) then
            vim.api.nvim_buf_delete(instance.buffer_number, { force = true })
        end
        M._instance = nil
    end

    local sessions = M.list_sessions()
    if #sessions == 0 then
        log:warn("No sessions found to restore")
        return nil
    end

    ---@class SessionRestoreList : FloatWindow
    ---@field sessions SessionEntry[]
    ---@field selected_idx integer
    local instance_mt = { __index = FloatWindow }
    local instance = setmetatable(FloatWindow:new({
        width_ratio = 0.5,
        height_ratio = 0.5,
        filetype = "markdown",
        buffer_name = "AskSessionRestore",
    }), instance_mt)

    instance.sessions = sessions
    instance.selected_idx = 1

    -- * track instance at module level
    M._instance = instance

    -- * render initial list
    M.render_list(instance)

    -- * buffer-local keymaps
    vim.keymap.set("n", "<Down>", function()
        M.move_selection_down(instance)
    end, { buffer = instance.buffer_number, noremap = true, silent = true })

    vim.keymap.set("n", "j", function()
        M.move_selection_down(instance)
    end, { buffer = instance.buffer_number, noremap = true, silent = true })

    vim.keymap.set("n", "<Up>", function()
        M.move_selection_up(instance)
    end, { buffer = instance.buffer_number, noremap = true, silent = true })

    vim.keymap.set("n", "k", function()
        M.move_selection_up(instance)
    end, { buffer = instance.buffer_number, noremap = true, silent = true })

    vim.keymap.set("n", "<CR>", function()
        M.restore_selected(instance)
    end, { buffer = instance.buffer_number, noremap = true, silent = true })

    vim.keymap.set("n", "q", function()
        M.close(instance)
    end, { buffer = instance.buffer_number, noremap = true, silent = true })

    -- * set title
    instance:set_title("Session Restore (" .. #sessions .. " sessions)")

    return instance
end

--- Render the session list into the window buffer.
---
---@param instance SessionRestoreList
function M.render_list(instance)
    local lines = {}
    for idx, entry in ipairs(instance.sessions) do
        local entry_lines = format_entry_lines(entry, idx)
        table.insert(lines, entry_lines[1]) -- header line (always visible)

        if idx == instance.selected_idx then
            -- Highlight selected item's content with a special marker
            table.insert(lines, "  >> " .. entry_lines[2])
        else
            table.insert(lines, "     " .. entry_lines[2])
        end
    end

    vim.api.nvim_buf_set_lines(instance.buffer_number, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { instance.selected_idx * 2 - 1, 0 })
end

--- Move selection down by one.
---
---@param instance SessionRestoreList
function M.move_selection_down(instance)
    if instance.selected_idx < #instance.sessions then
        instance.selected_idx = instance.selected_idx + 1
        M.render_list(instance)
    end
end

--- Move selection up by one.
---
---@param instance SessionRestoreList
function M.move_selection_up(instance)
    if instance.selected_idx > 1 then
        instance.selected_idx = instance.selected_idx - 1
        M.render_list(instance)
    end
end

--- Restore the selected session into the chat viewer window and close this list.
---
---@param instance SessionRestoreList
function M.restore_selected(instance)
    local selected_entry = instance.sessions[instance.selected_idx]
    if not selected_entry then
        return
    end

    log:info("Restoring session: " .. selected_entry.session_id)

    -- Close the restore list window first (this also sets M._instance = nil)
    M.close(instance)

    -- Restore the session (uses vim.schedule internally)
    local trace_restorer = require("ask-openai.agents.viewer.trace_restorer")
    local success = trace_restorer.restore_session(selected_entry.trace_path)
    if not success then
        log:error("Failed to restore session: " .. selected_entry.session_id)
    end
end

--- Close the restore list window and clean up the instance.
--- Uses FloatWindow:close() for proper cleanup.
---
---@param instance SessionRestoreList
function M.close(instance)
    -- Use FloatWindow:close() which handles both window AND buffer cleanup
    instance:close()

    -- Clear the module-level reference so it can be recreated
    M._instance = nil
end

return M
