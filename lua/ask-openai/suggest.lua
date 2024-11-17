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

    local config = require("ask-openai.config")
    local copilot = config.get_provider()
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
        print("Request failed:", response.status, response.body)
        " prepend : to make it extra obvious (b/c cmdline already has a : so this doubles it up, still works just fine)
        return ':messages " request failed, run this to see why'
    end
end
