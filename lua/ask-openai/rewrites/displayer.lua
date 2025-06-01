local log = require("ask-openai.prediction.logger").predictions()

---@class Displayer
local Displayer = {}
Displayer.__index = Displayer

-- TODO move over concepts like ExtmarksSet (AFTER I GET DIFF GOING)
-- local prediction_namespace = vim.api.nvim_create_namespace('zeta-prediction')

function Displayer:new()
    self = setmetatable({}, Displayer)
    return self
end

function Displayer:accept()
    -- TODO move logic to accept here, later
    self:remove_keymaps()
end

function Displayer:reject()
    self:remove_keymaps()
end

function Displayer:set_keymaps()
    function accept()
        vim.schedule(function()
            log:info('Accepting')
            self:accept()
        end)
    end

    -- TODO pick if I want tab or alt-tab?
    vim.keymap.set({ 'i', 'n' }, '<Tab>', accept, { expr = true, buffer = true })
    vim.keymap.set({ 'i', 'n' }, '<M-Tab>', accept, { expr = true, buffer = true })

    function reject()
        vim.schedule(function()
            log:info('Rejecting')
            self:reject()
        end)
    end

    vim.keymap.set({ 'i', 'n' }, '<Esc>', reject, { expr = true, buffer = true })
    vim.keymap.set({ 'i', 'n' }, '<M-Esc>', reject, { expr = true, buffer = true })
end

function Displayer:remove_keymaps()
    -- TODO get rid of fallbacks? Alt-Tab/Esc shouldn't be needed
    vim.cmd([[
      silent! iunmap <buffer> <Tab>
      silent! iunmap <buffer> <Esc>
      silent! iunmap <buffer> <M-Tab>
      silent! iunmap <buffer> <M-Esc>

      silent! nunmap <buffer> <Tab>
      silent! nunmap <buffer> <Esc>
      silent! nunmap <buffer> <M-Tab>
      silent! nunmap <buffer> <M-Esc>
    ]])
end

return Displayer
