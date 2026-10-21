local config = require("ask-openai.config")
local log = require("devtools.logs.logger").universal()

local M = {}

local function setup_keymaps()
    -- *** switch copilot keymaps:
    -- WEIRD, after iterm crash, or some other factor, F15 stopped working and I get S-F3 instead? using Ctrl-v ... WTH?
    --   '<S-F3>' '<F15>'

    local common_options = { noremap = true, silent = true }
    vim.keymap.set({ 'n', 'i', 'v', 'c' }, '<F18>', config.toggle_predictions, common_options)
    --
    -- <F41> == <C-S-F5> (Keyboard Maestro => use <C-S-...> for higher Function keys (menu only picks up to F20 otherwise)
    vim.keymap.set({ 'n', 'i', 'v', 'c' }, '<F41>', config.toggle_fim_model, common_options)
    -- <F42> = <C-S-F6>
    vim.keymap.set({ 'n', 'i', 'v', 'c' }, '<F42>', function() config.toggle_rewrite_model() end, common_options)
    -- <F43> = <C-S-F7>
    vim.keymap.set({ 'n', 'i', 'v', 'c' }, '<F43>', config.toggle_agents_model, common_options)
    --
    -- <M-S-F5> (btw matches C-S-F5 used for model cycler for same frontend
    vim.keymap.set({ 'n', 'i', 'v', 'c' }, '<M-S-F5>', config.cycle_fim_reasoning_level, common_options)
    -- <M-S-F6>
    vim.keymap.set({ 'n', 'i', 'v', 'c' }, '<M-S-F6>', config.cycle_rewrite_reasoning_level, common_options)
    -- <M-S-F7>
    vim.keymap.set({ 'n', 'i', 'v', 'c' }, '<M-S-F7>', config.cycle_agents_reasoning_level, common_options)
    --
    -- misc:
    vim.keymap.set({ 'n', 'i', 'v', 'c' }, '<F17>', config.toggle_rag, common_options)
end

function M.setup()
    config.setup()

    require("ask-openai.cmdline.suggest").setup()
    require("ask-openai.predictions.frontend").setup()
    require("ask-openai.frontends.context").setup()
    require("ask-openai.rewrites.frontend").setup()
    require("ask-openai.agents.frontend").setup()
    require("ask-openai.tools.mcp").setup()
    require("ask-openai.rag").setup()
    require("ask-openai.voiced").setup()
    require("ask-openai.clankerd").setup()

    setup_keymaps()
end

return M
