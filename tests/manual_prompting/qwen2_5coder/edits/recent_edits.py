from show import show_completion_for

# FYI run as a module (not script):
#   i.e. `python -m file_level_fim`
#   `python -m file_name_without_ext` b/c then I can keep shared show lib in dir above and nest diff "modules" in dirs like "worked"

# this is gonna be context to see if it will pay attention
ring_buffer_file = "local RingBuffer = {}\nRingBuffer.__index = RingBuffer\n\nfunction RingBuffer.new(size)\n    return setmetatable({\n        size = size,\n        data = {},\n        head = 0,\n        count = 0,\n    }, RingBuffer)\nend\n\nfunction RingBuffer:push(item)\n    self.head = (self.head % self.size) + 1\n    self.data[self.head] = item\n    if self.count < self.size then\n        self.count = self.count + 1\n    end\nend\n\nfunction RingBuffer:items()\n    local items = {}\n    for i = 1, self.count do\n        local index = ((self.head - i + self.size) % self.size) + 1\n        table.insert(items, self.data[index])\n    end\n    return items\nend"

request_body = {
    "prompt": "<|repo_name|>maths\n<|file_sep|>calc.lua\n<|fim_prefix|>local M = {}\n\nfunction M.add(a, b)\n    return a + b\nend\n\n<|fim_suffix|>\n\n\nreturn M<|fim_middle|>",
    "options": {
        "num_ctx": 1024
    },
    "raw": True,
    "num_predict": 200,
    "stream": False,
    "model": "qwen2.5-coder:7b-base-q8_0",
}

show_completion_for(request_body)
