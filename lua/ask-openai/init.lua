local function trim_null_characters(input)
    -- Replace null characters (\x00) with an empty string
    -- was getting ^@ at end of command output w/ system call (below)
    if input == nil then
        return ""
    end
    return input:gsub("%z", "")
end

local function ask_openai()
    local cmdline = vim.fn.getcmdline()
    print("asking...") -- overwrites showing luaeval("...") in cmdline

    local stdin_text = ' env: nvim (neovim) command mode (return a valid command w/o the leading : ) \n question: ' ..
        cmdline

    local suggest = require("ask-openai.suggest")
    local result = suggest.get_vim_command_suggestion(stdin_text)
    return trim_null_characters(result)
end

--- @param options AskOpenAIOptions
local function setup(options)
    -- MAYBE remove setup and let it be implicit? that said I like only wirting up the key if someone calls this
    require("ask-openai.config").set_user_options(options) -- MAYBE I can move this out to elsewhere, isn't there a config method for this?

    -- [e]valuate vimscript expression luaeval("...") which runs nested lua code
    -- DO NOT SET silent=true, messes up putting result into cmdline, also I wanna see print messages, IIUC that would be affected
    -- FYI `<C-\>e` is critical in the following, don't remove the `e` and `\\` is to escape the `\` in lua
    vim.api.nvim_set_keymap('c', '<C-b>', '<C-\\>eluaeval("require(\'ask-openai\').ask_openai()")<CR>',
        { noremap = true, })
end

return {
    setup = setup,
    ask_openai = ask_openai,
}
