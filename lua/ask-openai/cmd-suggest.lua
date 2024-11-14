local curl = require('plenary.curl')

local M = {}

local function get_cmd_suggestion(passed_context)
    local system_message = [[
        You are a vim expert. The user (that you are talking to) has vim open in command mode.
        They have typed part of a command that they need help with.
        They might also have a question included, i.e., in a comment (after " which denotes a comment in vim).
        Respond with a single, valid vim command line. Their command line will be replaced with your response so it can be reviewed and executed.
        No explanation. No markdown. No markdown with backticks ` nor ```.

        If the user mentions another vim mode (i.e., normal, insert, etc.), then if possible return a command to switch to that mode and execute whatever they asked about.
        For example, if the user asks how to delete a line in normal mode, you could answer `:normal dd`.
    ]]

    local key = require("ask-openai.key")
    local api_key = key.get_openai_key()
    if not api_key then
        return "API key not set, please check keychain" -- shows in cmdline is fine
    end

    local model = require("ask-openai.config").user_opts.model

    local response = curl.post({
        url = "https://api.openai.com/v1/chat/completions",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. api_key
        },
        body = vim.json.encode({
            model = model,
            messages = {
                { role = "system", content = system_message },
                { role = "user",   content = passed_context }
            },
            max_tokens = 200,
            n = 1
        }),
        synchronous = true
    })

    if response and response.status == 200 then
        local result = vim.json.decode(response.body)
        return result.choices[1].message.content
    else
        -- FYI in luaeval, cannot have some side effects (modify buffer) so notify won't work directly but it can be scheduled to work
        -- vim.schedule(function()
        --     -- FYI shows dimmed until done editing command line
        --     vim.notify("Request failed: " .. response.status .. " " .. response.body)
        -- end)

        -- FYI `:messages` will show this, if need to be obvious use notify
        print("Request failed:", response.status, response.body)
        return "Request failed, see :messages"
    end
end

local function trim_null_characters(input)
    -- Replace null characters (\x00) with an empty string
    -- was getting ^@ at end of command output w/ system call (below)
    if input == nil then
        return ""
    end
    return input:gsub("%z", "")
end

function M.setup_cmd_suggestions()
    function AskOpenAILua()
        -- leave name slightly different so no confusion about vimscript func vs lua func

        local cmdline = vim.fn.getcmdline()

        local stdin_text = ' env: nvim (neovim) command mode (return a valid command w/o the leading : ) \n question: ' ..
            cmdline

        local result = get_cmd_suggestion(stdin_text)

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
end

return M
