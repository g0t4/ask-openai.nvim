--- Low-level Unix socket client for the voiced daemon.
---
--- Talks to ~/.local/state/ask-openai/voiced.sock using newline-delimited
--- JSON. Data is buffered and split on newlines before JSON decoding.

local M = {}

local log = require("devtools.logs.logger").universal()

local socket_path = vim.env.HOME .. "/.local/state/ask-openai/voiced.sock"

local channel = nil
local buffer = ""
local handlers = {}

local function handle_line(line)
    line = line:gsub("%s+$", "")
    if line == "" then
        return
    end
    local ok, event = pcall(vim.json.decode, line)
    if not ok then
        log:info("voiced: bad json line", line)
        return
    end
    local handler = handlers[event.type]
    if handler then
        handler(event)
    end
end

local function on_data(_, data)
    -- data is a readfile()-style list of strings, where each element is a
    -- newline-stripped line (the trailing newline shows up as an empty '').
    -- Re-join with newlines to reconstruct the stream, then split.
    buffer = buffer .. table.concat(data, "\n")
    while true do
        local newline = buffer:find("\n", 1, true)
        if not newline then
            break
        end
        local line = buffer:sub(1, newline - 1)
        buffer = buffer:sub(newline + 1)
        handle_line(line)
    end
end

---@return integer|nil channel id
function M.connect()
    if channel then
        return channel
    end
    local ok, result = pcall(vim.fn.sockconnect, "pipe", socket_path, {
        on_data = on_data,
    })
    if not ok then
        log:info("voiced: connect failed", result)
        return nil
    end
    channel = result
    log:info("voiced: connected on channel", channel)
    return channel
end

---@param payload table
---@return boolean sent
function M.send(payload)
    if not channel then
        M.connect()
    end
    if not channel then
        return false
    end
    local json = vim.json.encode(payload)
    vim.fn.chansend(channel, json .. "\n")
    return true
end

---@param event_type string
---@param handler fun(event: table)
function M.set_handler(event_type, handler)
    handlers[event_type] = handler
end

return M
