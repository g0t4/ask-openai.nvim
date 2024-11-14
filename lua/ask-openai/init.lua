local M = {}

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

    local hints = require("ask-openai.hints")
    hints.setup_hints()
end

return M
