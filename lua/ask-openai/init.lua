local _module = {}

local config = require("ask-openai.config")

local is_predictions_enabled_runtime = false

function _module.is_predictions_enabled()
    -- todo organize top level funcs on a module instead
    return is_predictions_enabled_runtime
end

local augroup = "ask-openai.prediction"

local function register_prediction_triggers()
    local handlers = require("ask-openai.prediction.handlers")

    local predictions = config.get_options().tmp.predictions
    if not predictions.keymaps then
        config.print_verbose("predictions.keymaps is disabled, skipping")
        return
    end

    -- keymaps
    if predictions.keymaps.accept_all then
        vim.api.nvim_set_keymap('i', predictions.keymaps.accept_all, "",
            { noremap = true, callback = handlers.accept_all_invoked })
    end

    if predictions.keymaps.accept_line then
        vim.api.nvim_set_keymap('i', predictions.keymaps.accept_line, "",
            { noremap = true, callback = handlers.accept_line_invoked })
    end

    if predictions.keymaps.accept_word then
        vim.api.nvim_set_keymap('i', predictions.keymaps.accept_word, "",
            { noremap = true, callback = handlers.accept_word_invoked })
    end

    if predictions.keymaps.pause_stream then
        vim.api.nvim_set_keymap('i', predictions.keymaps.pause_stream, "", {
            noremap = true,
            callback = handlers.pause_stream_invoked,
        })
    end

    if predictions.keymaps.resume_stream then
        vim.api.nvim_set_keymap('i', predictions.keymaps.resume_stream, "", {
            noremap = true,
            callback = handlers.resume_stream_invoked,
        })
    end

    -- FYI why don't I reserve ~ for debug keymap(s) and move it around to w/e I need it for currently?
    --   ~ not intended as a permanent keymap here
    vim.keymap.set("n", "<leader>~", "<cmd>AskDumpEdits<CR>", {})

    -- event subscriptions
    vim.api.nvim_create_augroup(augroup, { clear = true })
    vim.api.nvim_create_autocmd("InsertLeavePre", {
        group = augroup,
        pattern = "*",
        callback = handlers.leaving_insert_mode
    })
    vim.api.nvim_create_autocmd("InsertEnter", {
        group = augroup,
        pattern = "*",
        callback = handlers.entering_insert_mode
    })
    -- vim.api.nvim_create_autocmd("CursorMovedI", {
    --     -- TODO TextChangedI intead of cursor moved?
    --     group = augroup,
    --     pattern = "*", -- todo filter?
    --     callback = handlers.cursor_moved_in_insert_mode
    -- })
    vim.api.nvim_create_autocmd("TextChangedI", {
        -- do I like this better? is this gonna mess up when I insert text still?
        group = augroup,
        pattern = "*",
        callback = handlers.cursor_moved_in_insert_mode,
    })

    -- SETUP hlgroup
    -- TODO make this configurable
    vim.api.nvim_set_hl(0, "AskPrediction", { italic = true, fg = "#dddddd" }) -- FYI can call repeatedly and no errors

    is_predictions_enabled_runtime = true
end

function _module.remove_prediction_triggers()
    -- FYI pcall blocks error propagation (returns status code, though in this case I don't care about that)
    -- remove event triggers
    pcall(vim.api.nvim_del_augroup_by_name, augroup) -- most del methods will throw if doesn't exist... so just ignore that

    local predictions = config.get_options().tmp.predictions
    if not predictions.keymaps then
        config.print_verbose("predictions.keymaps is disabled, skipping")
        return
    end

    -- remove keymaps
    pcall(vim.api.nvim_del_keymap, 'i', predictions.keymaps.accept_all)
    pcall(vim.api.nvim_del_keymap, 'i', predictions.keymaps.accept_line)
    pcall(vim.api.nvim_del_keymap, 'i', predictions.keymaps.accept_word)
    pcall(vim.api.nvim_del_keymap, 'i', predictions.keymaps.pause_stream)
    pcall(vim.api.nvim_del_keymap, 'i', predictions.keymaps.resume_stream)
end

function _module.enable_predictions()
    if not config.get_options().tmp.predictions.enabled then
        -- if disabled in config, then never enable
        return
    end
    if is_predictions_enabled_runtime then
        return
    end
    register_prediction_triggers()
    is_predictions_enabled_runtime = true
end

function _module.disable_predictions()
    if not is_predictions_enabled_runtime then
        return
    end
    _module.remove_prediction_triggers()
    is_predictions_enabled_runtime = false
end

local function trim_null_characters(input)
    -- Replace null characters (\x00) with an empty string
    -- was getting ^@ at end of command output w/ system call (below)
    if input == nil then
        return ""
    end
    return input:gsub("%z", "")
end

function _module.ask_openai()
    local cmdline = vim.fn.getcmdline()
    print("asking...") -- overwrites showing luaeval("...") in cmdline

    local stdin_text = ' env: nvim (neovim) command mode (return a valid command w/o the leading : ) \n question: ' ..
        cmdline

    local suggest = require("ask-openai.suggest")
    local result = suggest.get_vim_command_suggestion(stdin_text)
    return trim_null_characters(result)
end

--- @param options AskOpenAIOptions
function _module.setup(options)
    -- MAYBE remove setup and let it be implicit? that said I like only wirting up the key if someone calls this
    config.set_user_options(options) -- MAYBE I can move this out to elsewhere, isn't there a config method for this?

    local lhs = config.get_options().keymaps.cmdline_ask
    if not lhs then
        config.print_verbose("cmdline_ask keymap is disabled, skipping")
        return
    end

    -- [e]valuate vimscript expression luaeval("...") which runs nested lua code
    -- DO NOT SET silent=true, messes up putting result into cmdline, also I wanna see print messages, IIUC that would be affected
    -- FYI `<C-\>e` is critical in the following, don't remove the `e` and `\\` is to escape the `\` in lua
    vim.api.nvim_set_keymap('c', lhs, '<C-\\>eluaeval("require(\'ask-openai\').ask_openai()")<CR>', { noremap = true, })

    _module.enable_predictions()

    require("ask-openai.rewrites.inline").setup()
    require("ask-openai.questions.ask").setup()
    require("ask-openai.tools.mcp").setup()
end

return _module
