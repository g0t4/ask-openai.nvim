local RingBuffer = {}
RingBuffer.__index = RingBuffer

function RingBuffer.new(size)
    return setmetatable({
        size = size,
        data = {},
        head = 0,
        count = 0,
    }, RingBuffer)
end

function RingBuffer:push(item)
    self.head = (self.head % self.size) + 1
    self.data[self.head] = item
    if self.count < self.size then
        self.count = self.count + 1
    end
end

function RingBuffer:items()
    local items = {}
    for i = 1, self.count do
        local index = ((self.head - i + self.size) % self.size) + 1
        table.insert(items, self.data[index])
    end
    return items
end
