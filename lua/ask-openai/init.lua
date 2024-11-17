local M = {}

function M.setup(opts)
    require("ask-openai.config").set_user_opts(opts)
    require("ask-openai.suggest")

    -- TODO modify this to use github copilot subscription/api using chat model and see how it performs vs openai gpt4o (FYI windows terminal chat w/ copilot was clearly inferior vs gpt4o but ... win term chat might have been using gpt3.5 or smth else, just FYI"

    local function trim_null_characters(input)
        -- Replace null characters (\x00) with an empty string
        -- was getting ^@ at end of command output w/ system call (below)
        if input == nil then
            return ""
        end
        return input:gsub("%z", "")
    end

    function ask_openai()
        local cmdline = vim.fn.getcmdline()
        print("asking...") -- overwrites showing luaeval("ask_openai()") in cmdline, this looks better, could also do print("AskOpenAI()") if I want to go back to the previous style

        local stdin_text = ' env: nvim (neovim) command mode (return a valid command w/o the leading : ) \n question: ' ..
            cmdline

        local result = get_vim_command_suggestion(stdin_text)
        return trim_null_characters(result)
    end

    -- [e]valuate expression luaeval("ask_openai()") in command-line mode
    -- DO NOT SET silent=true, messes up putting result into cmdline, also I wanna see print messages, IIUC that would be affected
    -- FYI `<C-\>e` is critical in the following, don't remove the `e` and `\\` is to escape the `\` in lua
    vim.api.nvim_set_keymap('c', '<C-b>', '<C-\\>eluaeval("ask_openai()")<CR>', { noremap = true, })
end

return M
