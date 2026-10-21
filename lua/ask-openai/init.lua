local config = require("ask-openai.config")
local log = require("devtools.logs.logger").universal()

local M = {}

local function setup_keymaps()
    -- *** switch copilot keymaps:
    -- WEIRD, after iterm crash, or some other factor, F15 stopped working and I get S-F3 instead? using Ctrl-v ... WTH?
    --   '<S-F3>' '<F15>'

    vim.keymap.set({ 'n', 'i', 'v', 'c' }, '<F18>', config.toggle_predictions, { noremap = true, silent = true }) -- TODO remove?
    --
    -- <F41> == <C-S-F5> (Keyboard Maestro => use <C-S-...> for higher Function keys (menu only picks up to F20 otherwise)
    vim.keymap.set({ 'n', 'i', 'v', 'c' }, '<F41>', config.toggle_fim_model,
        { noremap = true, silent = true })
    -- <F42> = <C-S-F6>
    vim.keymap.set({ 'n', 'i', 'v', 'c' }, '<F42>',
        function() config.toggle_rewrite_model() end,
        { noremap = true, silent = true })
    -- <F43> = <C-S-F7>
    vim.keymap.set({ 'n', 'i', 'v', 'c' }, '<F43>', config.toggle_agents_model,
        { noremap = true, silent = true })
    --
    -- <M-S-F5> (btw matches C-S-F5 used for model cycler for same frontend
    vim.keymap.set({ 'n', 'i', 'v', 'c' }, '<M-S-F5>',
        config.cycle_fim_reasoning_level, { noremap = true, silent = true })
    -- <M-S-F6>
    vim.keymap.set({ 'n', 'i', 'v', 'c' }, '<M-S-F6>',
        config.cycle_rewrite_reasoning_level,
        { noremap = true, silent = true })
    -- <M-S-F7>
    vim.keymap.set({ 'n', 'i', 'v', 'c' }, '<M-S-F7>',
        config.cycle_agents_reasoning_level, { noremap = true, silent = true })
    --
    -- misc:
    vim.keymap.set({ 'n', 'i', 'v', 'c' }, '<F17>', config.toggle_rag,
        { noremap = true, silent = true })
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
