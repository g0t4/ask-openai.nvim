local curl = require('plenary.curl')

local M = {} -- TODO use module pattern

function get_api_key_from_keychain()
    local handle = io.popen('security find-generic-password -s openai -a ask -w')
    if handle then
        local api_key = handle:read("*a"):gsub("%s+", "") -- remove any extra whitespace
        handle:close()
        return api_key
    else
        print("Failed to retrieve API key from Keychain.")
        return nil
    end
end

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

    local api_key = get_api_key_from_keychain()
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
        local completion = result.choices[1].message.content

        log_response(passed_context, model, completion)
        return completion
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

function log_response(context, model, response)
    local log_path = vim.fn.expand(require("ask-openai.config").user_opts.log_path)
    local file = io.open(log_path, "a")
    if file then
        file:write("Context: " .. context .. "\n")
        file:write("Model: " .. model .. "\n")
        file:write("Response: " .. response .. "\n\n")
        file:close()
    else
        print("Failed to write to log file.")
    end
end
