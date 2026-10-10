--- ask-openai voice module: connects to the voiced daemon and surfaces live
--- transcriptions in Neovim.

local M = {}

local client = require("ask-openai.voiced.client")
local log = require("devtools.logs.logger").universal()

local function on_transcription(event)
    local text = event.text or ""
    local is_final = event.final or false
    log:info("voiced transcription" .. (is_final and " [final]" or ""), text)
    local prefix = is_final and "[voiced ✓] " or "[voiced] "
    print(prefix .. text)
end

local function on_status(event)
    log:info("voiced status", event.state)
end

function M.setup()
    client.set_handler("transcription", on_transcription)
    client.set_handler("status", on_status)
    client.set_handler("pong", function()
        log:info("voiced pong")
    end)
    client.set_handler("error", function(event)
        log:info("voiced error", event.message)
    end)

    client.connect()

    vim.api.nvim_create_user_command("VoicedStart", function()
        client.send({ type = "start" })
    end, { desc = "Start voiced listening" })

    vim.api.nvim_create_user_command("VoicedStop", function()
        client.send({ type = "stop" })
    end, { desc = "Stop voiced listening" })

    vim.api.nvim_create_user_command("VoicedStatus", function()
        client.send({ type = "ping" })
    end, { desc = "Ping the voiced daemon" })
end

return M
