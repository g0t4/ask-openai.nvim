local M = {}

local log_path = vim.fn.fnamemodify("ask.log", ":p")

function AskClearLogs()
    local log_file = io.open(log_path, "w")

    if log_file then
        log_file:close()
    else
        vim.api.nvim_err_writeln("Failed to open log file: " .. log_path)
    end
end

AskClearLogs()

local function log_message(message)
    local log_file = io.open(log_path, "a")

    if log_file then
        -- time is useful to group keystrokes
        log_file:write(os.date("%H:%M:%S") .. " - " .. message .. "\n")
        log_file:close()
    else
        vim.api.nvim_err_writeln("Failed to open log file: " .. log_path)
    end
end

local function refresh_log_view()
    -- Check if the log file buffer is loaded
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == log_path then
            -- Reload the buffer if the file changed outside Vim
            vim.api.nvim_command("checktime " .. buf)
            -- scroll the log buffer to the bottom:
            --  w/o indirect keystrokes that muddle logs
            local win_id = vim.fn.bufwinid(buf)
            if win_id ~= -1 and win_id ~= nil then
                local line_count = vim.api.nvim_buf_line_count(buf)
                -- log_message("win_id: " .. win_id .. ", line_count: " .. line_count)
                vim.api.nvim_win_set_cursor(win_id, { line_count, 0 })
            end
        end
    end
end

local refresh_timer

local function signal_refresh_log_view()
    -- if series of keystrokes pressed, wait until series is done  and then trigger log refresh
    if refresh_timer then
        refresh_timer:stop() -- Stop the previous timer if it's still running
    end

    refresh_timer = vim.defer_fn(refresh_log_view, 300) -- ms
end

local function setup_hints()
    -- PRN make this local?
    if not require("ask-openai.config").user_opts.on_the_fly_hints then
        return
        -- TODO make runtime TOGGLE
    end

    -- TODO setup some sort of integration testing to figure out what keys map to what, don't keep testing this manually
    local last_keys = ""

    vim.on_key(function(key_after_mapping, key_before_mapping)
        local mode = vim.fn.mode()
        -- ignore if keystroke is in buffer for log view
        if vim.api.nvim_get_current_buf() == vim.fn.bufnr(log_path) then
            -- otherwise, things like g`" to restore cursor will repeatedly be logged and trigger log refresh in an infinite loop
            return
        end

        local key = vim.fn.keytrans(key_before_mapping)
        -- FYI:
        --   hardtime blocks arrows and so if I type <Up> it shows up in the next keystroke:
        --     mode n, key: <Up><Up><Up>a, before: ?ku?ku?kua, after: a
        --     add this to prompt, or, map to a single key per on_key and then concat into one giant string so it doesn't matter?
        --     in some cases, I might want to ignore if (keytrans is empty) and other cases replace keytrans?

        log_message("mode " ..
            mode .. ", key: " .. key .. ", before: " .. key_before_mapping .. ", after: " .. key_after_mapping)
        -- log_message("mode " .. mode .. ", key: " .. key)
        -- TODO will need to optionally filter on some key maps, i.e. neoscroll uses a series of `gk`/`gj` to scroll page up/down, but can see ctrl+d/u etc right before that and ignore it
        --  actually in ctrl+d/u case => keytrans doesn't return g/j, just before mapping shows it, so I can filter that
        --  if key_after is empty then filter it out, was not a typed key (i.e. ctrl+d/u)

        signal_refresh_log_view()

        last_keys = key .. "\n" .. last_keys

        -- local match = string.find(key, "<C-", 1, true)

        -- TODO when to clear last_keys? maybe after get suggestion?
        -- ! FYI I am not sure I wanna ask on every keypress, just means might have some delayed suggestions?
        --   MAYBE it would be better to just create more hints ihn hardtime? and be done with it?
    end)
end

function M.setup(opts)
    require("ask-openai.cmd-suggest")

    require("ask-openai.config").set_user_opts(opts)

    -- TODO modify this to use github copilot subscription/api using chat model and see how it performs vs openai gpt4o (FYI windows terminal chat w/ copilot was clearly inferior vs gpt4o but ... win term chat might have been using gpt3.5 or smth else, just FYI"

    local function trim_null_characters(input)
        -- Replace null characters (\x00) with an empty string
        -- was getting ^@ at end of command output w/ system call (below)
        if input == nil then
            return ""
        end
        return input:gsub("%z", "")
    end

    function AskOpenAILua()
        -- leave name slightly different so no confusion about vimscript func vs lua func
        local cmdline = vim.fn.getcmdline()

        local stdin_text = ' env: nvim (neovim) command mode (return a valid command w/o the leading : ) \n question: ' ..
            cmdline

        local result = GetCommandSuggestion(stdin_text)

        return trim_null_characters(result)
    end

    vim.cmd [[
        function! AskOpenAI()
            " just a wrapper so the CLI shows "AskOpenAI" instead of "luaeval('AskOpenAILua()')"
            return luaeval('AskOpenAILua()')
            " also, FYI, luaeval and the nature of a cmap modifying cmdline means there really is no way to present errors short of putting them into the command line, which is fine and how I do it in my CLI equivalents of this
            "   only issue w/ putting into cmdline is no UNDO AFAIK for going back to what you had typed... unlike how I can do that in fish shell and just ctrl+z to undo the error message, but error messages are gonna be pretty rare so NBD for now
        endfunction
    ]]

    -- [e]valuate expression AskOpenAI() in command-line mode
    -- DO NOT SET silent=true, messes up putting result into cmdline
    vim.api.nvim_set_keymap('c', '<C-b>', '<C-\\>eAskOpenAI()<CR>', { noremap = true, })

    setup_hints()
end

return M
