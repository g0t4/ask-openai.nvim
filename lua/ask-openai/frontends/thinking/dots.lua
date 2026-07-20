local perf = require("ask-openai.perf")

local M = {}

M.count = 0
M.dots = ""

--- Converts seconds to a human-readable string (e.g., "1h 2m 3s").
---@param seconds number
---@return string
local function human_duration_from_seconds(seconds)
    local hrs = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    local parts = {}
    if hrs > 0 then table.insert(parts, hrs .. "h") end
    if mins > 0 then table.insert(parts, mins .. "m") end
    if secs > 0 or (#parts == 0) then table.insert(parts, secs .. "s") end
    return table.concat(parts, " ")
end

--- Updates the dot state for a given controller instance.
---@param self table The controller instance.
local function update_dot_state(self)
    self.count = self.count + 1

    local should_add_dot = self.count % 4 == 0
    local should_reset = self.count > 120

    if should_add_dot then
        self.dots = (self.dots or "") .. "."
    end

    if should_reset then
        self.dots = ""
        self.count = 0
    end
end

function M:_message(elapsed_seconds)
    update_dot_state(self)
    local duration = human_duration_from_seconds(elapsed_seconds)
    return "thinking: " .. duration .. " ⏳" .. (self.dots or M.dots)
end

--- Returns a "thinking" message with dot animation and duration.
---@param self table The controller instance.
function M:get_still_thinking_message(start_os_dot_time)
    local elapsed_seconds = os.time() - start_os_dot_time
    return self:_message(elapsed_seconds)
end

--- Returns a "thinking" message with dot animation and duration from nanoseconds.
---@param self table The controller instance.
function M:get_still_thinking_message_from_ns(start_time_ns)
    local elapsed_ns = perf.get_time_in_ns() - start_time_ns
    return self:_message(elapsed_ns / 1e9)
end

return M
