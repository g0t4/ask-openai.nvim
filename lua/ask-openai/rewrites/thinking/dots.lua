local M = {}

M.count = 0
M.dots = ""

function M.get_still_thinking_message(self)
    self.count = self.count + 1
    if self.count % 4 == 0 then
        self.dots = self.dots .. "."
    end
    if self.count > 120 then
        self.dots = ""
        self.count = 0
    end
    return "thinking: " .. M.dots
end

return M
