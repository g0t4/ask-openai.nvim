local RingBuffer = require("ask-openai.prediction.edits.ring_buffer")
local messages = require("devtools.messages")

local edit_log = RingBuffer.new(500)

vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    callback = function(args)
        local buf = args.buf
        local changedtick = vim.api.nvim_buf_get_changedtick(buf)
        local cursor = vim.api.nvim_win_get_cursor(0)
        local timestamp = vim.loop.now()

        -- PRN recurse into imported modules? or not?

        -- You can extract affected lines if you want, but for now track position
        edit_log:push({
            buf = buf,
            line = cursor[1],
            col = cursor[2],
            changedtick = changedtick,
            timestamp = timestamp,
        })
    end,
})
