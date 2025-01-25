local Prediction = {}
local uv = vim.uv


function Prediction:new()
    local prediction = {}
    -- id was originaly intended to track current prediction and not let past predictions write to extmarks (for example)
    prediction.id = uv.hrtime() -- might not need id if I can use object reference instead, we will see (id is helpful if I need to roundtrip identity outside lua process)
    -- (nanosecond) time based s/b sufficient, esp b/c there should only ever be one prediction at a time.. even if multiple in short time (b/c of keystrokes, there is gonna be 1ms or so between them at most)

    -- PRN prediction per buffer (only when not having this becomes a hassle)
    prediction.buffer = 0 -- 0 = CURRENT_BUFFER

    prediction.namespace_id = vim.api.nvim_create_namespace("ask-predictions")
    -- ?? keep \n to differentiate lines ? or map to some sort of object model (lines at least... and maybe tokenize the lines)
    prediction.prediction = ""
    prediction.extmarks = {}
    prediction.abandoned = false -- PRN could be a prediction state? IF NEEDED
    return setmetatable(prediction, { __index = Prediction })
end

function Prediction:add_chunk_to_prediction(chunk)
    self.prediction = self.prediction .. chunk
    self:redraw_extmarks()
end

function Prediction:redraw_extmarks()
    self:clear_extmarks()
    -- clear from 0 to -1 => entire buffer

    local original_row_1based, original_col = unpack(vim.api.nvim_win_get_cursor(0)) -- (1,0) based #s... aka original_row starts at 1, original_col starts at 0
    local original_row = original_row_1based - 1                                     -- 0-based now

    vim.api.nvim_buf_set_extmark(self.buffer, self.namespace_id, original_row, original_col,
        -- FYI, row,col are 0 based! ARGH FML
        {
            virt_text = { { self.prediction } },
            -- inline? for my testing? if I am at end of line it won't matter
            virt_text_pos = "overlay",
        })
end

function Prediction:clear_extmarks()
    -- clear from 0 to -1 => entire buffer
    vim.api.nvim_buf_clear_namespace(self.buffer, self.namespace_id, 0, -1)
end

function Prediction:mark_as_abandoned()
    self.abandoned = true
end

-- Predictions Notes:
-- - could request multiple predictions per buffer too, different parts -- i.e. to support a jump to edit feature (pie in sky)...
--  - can do this even as edits happen elsewhere... anchor the completion to part of the buffer that hasn't been modified


return Prediction
