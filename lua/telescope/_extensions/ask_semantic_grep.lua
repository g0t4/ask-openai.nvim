local actions = require 'telescope.actions'
local finders = require 'telescope.finders'
local pickers = require 'telescope.pickers'
local sorters = require 'telescope.sorters'
local state = require 'telescope.actions.state'

-- FYI the intent here is to test queries
-- but, if it proves useful then it might turn into a semantic picker
-- in fact... maybe this can turn an explicit, context selector (via actions?)!
-- for that I might also want regular old grep pickers too

local function picker(opts)
    -- GOOD examples (multiple pickers in one nvim plugin):
    --  https://gitlab.com/davvid/telescope-git-grep.nvim/-/blob/main/lua/git_grep/init.lua?ref_type=heads
    pickers
        .new(nil, {
            prompt_title = 'semantic grep - for testing RAG queries',
            finder = finders.new_table {
                results = { "hello", "world" },
            },
            sorter = sorters.get_generic_fuzzy_sorter(),
            attach_mappings = function(prompt_bufnr, keymap)
                actions.select_default:replace(function()
                    -- actions.close(prompt_bufnr)
                    local selection = state.get_selected_entry()
                    -- vim.api.nvim_command('vsplit ' .. link)
                    vim.print(selection)
                end)
                keymap({ 'i', 'n' }, 'c', function()
                    -- add to context
                    -- TODO add action for adding to an explicit context
                end)
                return true
            end,
        })
        :find()
end

return require('telescope').register_extension {
    exports = {
        -- setup
        ask_semantic_grep = picker,
        -- PRN other pickers!
    },
}
