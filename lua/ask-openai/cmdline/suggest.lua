local curl = require('plenary.curl')
local TxChatMessage = require('ask-openai.agents.messages.tx')
local log = require('devtools.logs.logger').universal()


local M = {}

---@return string
function M.get_vim_command_suggestion(passed_context)
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
    local base_url = config.get_endpoints().cmdline.base_url
    local completions_url = base_url .. "/v1/chat/completions"
    log:info("base_url", base_url)

    -- TODO switch to new Curl backend like with other frontends TO ENSURE TRACES are captured
    --  TODO or capture the traces here instead
    --  TODO can I stream in the tokens too so I see them one at a time?! I would love that versus having to build the response in one chunk (plus I can show thinking then too like rewrites)
    --  TODO good task to give Qwen to do (all of this, use RewriteFrontend as refernece... I would love to see a similar status indication like I have over there!

    local max_tokens = 10000 -- higher when using thinking models like 4K+ for gptoss120b (high 8K) and 10K for qwen3.6/agentworld
    local response = curl.post({
        url = completions_url,
        timeout = 30000,
        headers = {
            ["Content-Type"] = "application/json",
        },
        body = vim.json.encode({
            -- model = model, -- not used with llama-server currently
            messages = {
                TxChatMessage:system(system_message),
                TxChatMessage:user(passed_context),
            },
            max_tokens = max_tokens,
            n = 1,
            stream = false, -- FYI must set this for ollama, doesn't hurt to do for all
        }),
        synchronous = true -- might be fun to try to make this stream! not a huge value though for streaming a short cmdline but would teach me lua async
    })
    log:info("cmdline-response", vim.inspect(response))

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
        local first_choice = result.choices[1]
        local content = first_choice.message.content
        -- warn if first_choice finish_reason is length (turncated)
        if first_choice.finish_reason == "length" then
            content = content .. "\" content truncated, increase max token limits"
            log:warn("response was truncated due to token limit")
        end
        return content
    else
        log:error("Request failed:", response.status, response.body)
        -- prepend : to make it extra obvious (b/c cmdline already has a : this doubles up to ::, still works just fine)
        return ':messages " request failed, run this to see why'
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

function M.ask_suggest()
    local cmdline = vim.fn.getcmdline()
    print("asking...") -- overwrites showing luaeval("...") in cmdline

    local stdin_text = ' env: nvim (neovim) command mode (return a valid command w/o the leading : ) \n question: ' ..
        cmdline

    local suggest = require("ask-openai.cmdline.suggest")
    local result = suggest.get_vim_command_suggestion(stdin_text)
    return trim_null_characters(result)
end

function M.setup()
    -- [e]valuate vimscript expression luaeval("...") which runs nested lua code
    -- DO NOT SET silent=true, messes up putting result into cmdline, also I wanna see print messages, IIUC that would be affected
    -- FYI `<C-\>e` is critical in the following, don't remove the `e` and `\\` is to escape the `\` in lua
    vim.api.nvim_set_keymap('c', '<C-b>', '<C-\\>eluaeval("require(\'ask-openai.cmdline.suggest\').ask_suggest()")<CR>', { noremap = true, })
end

return M
