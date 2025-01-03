local curl = require('plenary.curl')

--- @return string
local function get_vim_command_suggestion(passed_context)
    local system_message = [[
        You are a vim expert. The user (that you are talking to) has vim open in command mode.
        They have typed part of a command that they need help with.
        They might also have a question included, i.e., in a comment (after " which denotes a comment in vim).
        Respond with a single, valid vim command line. Their command line will be replaced with your response so it can be reviewed and executed.
        No explanation. No markdown. No markdown with backticks ` nor ```.

        If the user mentions another vim mode (i.e., normal, insert, etc.), then if possible return a command to switch to that mode and execute whatever they asked about.
        For example, if the user asks how to delete a line in normal mode, you could answer `:normal dd`.
    ]]
    -- FYI local llama3.2-vision:11b works but it feels like it's more wrong than it should be... perhaps the prompt could be improved overall? mabye some examples?
    -- AVOID custom model prompts for now... should be generic
    -- PRN allow users to override the prompt?

    local config = require("ask-openai.config")
    local bearer_token = config.get_validated_bearer_token()
    local chat_url = config.get_chat_completions_url()
    config.print_verbose("chat_url", chat_url)
    local model = config.get_options().model
    config.print_verbose("model", model)

    local response = curl.post({
        url = chat_url,
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. bearer_token,
            ["Copilot-Integration-Id"] = "vscode-chat",
            ["Editor-Version"] = ("Neovim/%s.%s.%s")
                :format(vim.version().major, vim.version().minor, vim.version().patch),
            -- FYI watch messages for failures (i.e. when I didn't have Editor-Version set it choked)
        },
        body = vim.json.encode({
            model = model,
            messages = {
                { role = "system", content = system_message },
                { role = "user",   content = passed_context }
            },
            max_tokens = config.get_options().max_tokens,
            n = 1,
            stream = false, -- FYI must set this for ollama, doesn't hurt to do for all
        }),
        synchronous = true  -- might be fun to try to make this stream! not a huge value though for streaming a short cmdline but would teach me lua async
    })

    if response and response.status == 200 then
        -- vim.fn.writefile({ response.body }, "/tmp/ask-openai-response.json", "a")
        local result = vim.json.decode(response.body)
        if result.message then
            -- PRN check if choices is present first? then message?
            -- DERP use /v1/chat/completions (careful of fail messages on inavlid model, but yes this works so I dont need special request/response for ollama)
            -- ollama only returns a single choice (currently)
            return result.message.content
        end
        -- assume openai
        return result.choices[1].message.content
    else
        print("Request failed:", response.status, response.body)
        -- prepend : to make it extra obvious (b/c cmdline already has a : this doubles up to ::, still works just fine)
        return ':messages " request failed, run this to see why'
    end
end

return {
    get_vim_command_suggestion = get_vim_command_suggestion
}
