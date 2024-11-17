local curl = require('plenary.curl')

local M = {} -- TODO use module pattern

function get_vim_command_suggestion(passed_context)
    local system_message = [[
        You are a vim expert. The user (that you are talking to) has vim open in command mode.
        They have typed part of a command that they need help with.
        They might also have a question included, i.e., in a comment (after " which denotes a comment in vim).
        Respond with a single, valid vim command line. Their command line will be replaced with your response so it can be reviewed and executed.
        No explanation. No markdown. No markdown with backticks ` nor ```.

        If the user mentions another vim mode (i.e., normal, insert, etc.), then if possible return a command to switch to that mode and execute whatever they asked about.
        For example, if the user asks how to delete a line in normal mode, you could answer `:normal dd`.
    ]]

    -- local api_key = get_api_key_from_keychain()
    -- if not api_key then
    --     return "API key not set, please check keychain" -- shows in cmdline is fine
    -- end
    -- local chat_url = "https://api.openai.com/v1/chat/completions"

    local copilot = require("ask-openai.providers.copilot")
    local bearer_token = copilot.get_bearer_token()
    local chat_url = copilot.get_chat_completions_url()

    local model = require("ask-openai.config").user_opts.model

    local response = curl.post({
        url = chat_url,
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. bearer_token,
            ["Copilot-Integration-Id"] = "vscode-chat",
            ["Editor-Version"] = ("Neovim/%s.%s.%s"):format(vim.version().major, vim.version().minor, vim.version()
                .patch),
            -- FYI watch messages for failures (i.e. when I didn't have Editor-Version set it choked)
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
        synchronous = true -- might be fun to try to make this stream! not a huge value though for streaming a short cmdline but would teach me lua async
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
