local telescope = require("telescope")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local function all_pickers(opts)
    opts = opts or {}

    -- collect builtin pickers
    local builtin = require("telescope.builtin")
    local results = {}
    for k, _ in pairs(builtin) do
        table.insert(results, "builtin." .. k)
    end

    -- collect extension pickers
    for ext, mod in pairs(telescope.extensions) do
        for k, _ in pairs(mod) do
            table.insert(results, ext .. "." .. k)
        end
    end

    pickers.new(opts, {
        prompt_title = "One Picker to Rule them All, the 👃 knows Picker!",
        finder = finders.new_table { results = results },
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(bufnr, _)
            actions.select_default:replace(function()
                local entry = action_state.get_selected_entry()[1]
                actions.close(bufnr)
                -- split into ext/builtin + func
                local parts = vim.split(entry, "%.")
                if parts[1] == "builtin" then
                    builtin[parts[2]](opts)
                else
                    telescope.extensions[parts[1]][parts[2]](opts)
                end
            end)
            return true
        end,
    }):find()
end

vim.api.nvim_create_user_command("TelescopeAll", function()
    all_pickers()
end, {})
