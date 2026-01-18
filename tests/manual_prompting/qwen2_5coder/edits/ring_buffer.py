from show import show_completion_for

# python3 -m qwen2_5coder.edits.ring_buffer

# this is gonna be context to see if it will pay attention
ring_buffer_file = "<|file_sep|>ring.lua\nlocal RingBuffer = {}\nRingBuffer.__index = RingBuffer\n\nfunction RingBuffer.new(size)\n    return setmetatable({\n        size = size,\n        data = {},\n        head = 0,\n        count = 0,\n    }, RingBuffer)\nend\n\nfunction RingBuffer:push(item)\n    self.head = (self.head % self.size) + 1\n    self.data[self.head] = item\n    if self.count < self.size then\n        self.count = self.count + 1\n    end\nend\n\nfunction RingBuffer:items()\n    local items = {}\n    for i = 1, self.count do\n        local index = ((self.head - i + self.size) % self.size) + 1\n        table.insert(items, self.data[index])\n    end\n    return items\nend"

# FYI this doesn't include a require yet... lets just see if it can figure it out anyways
ring_current_01_minimal = "<|file_sep|>context.lua\n<|fim_prefix|>local edits = R<|fim_suffix|><|fim_middle|>"

request_body = {
    "prompt": "<|repo_name|>nvim\n" + ring_buffer_file + ring_current_01_minimal,
    "options": {
        "num_ctx": 1024
    },
    "raw": True,
    "num_predict": 200,
    "stream": False,
    "model": "qwen2.5-coder:7b-base-q8_0",
}

show_completion_for(request_body)
