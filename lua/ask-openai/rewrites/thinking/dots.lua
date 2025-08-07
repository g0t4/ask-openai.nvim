local M = {}

M.count = 0
M.dots = ""
M.start_time = nil

function M.set_start_time(self)
    self.start_time = os.time()
end

local function human_readable(seconds)
    local hrs = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    local parts = {}
    if hrs > 0 then table.insert(parts, hrs .. "h") end
    if mins > 0 then table.insert(parts, mins .. "m") end
    if secs > 0 or (#parts == 0) then table.insert(parts, secs .. "s") end
    return table.concat(parts, " ")
end

function M.get_still_thinking_message(self)
    self.count = self.count + 1
    if self.count % 4 == 0 then
        self.dots = self.dots .. "."
    end
    if self.count > 120 then
        self.dots = ""
        self.count = 0
    end
    local duration = ""
    if self.start_time then
        duration = human_readable(os.time() - self.start_time)
    end
    return "thinking: " .. duration .. " ⏳" .. M.dots
end

return M
