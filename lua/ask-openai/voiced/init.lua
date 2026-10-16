--- ask-openai voice module: connects to the voiced daemon and surfaces live
--- transcriptions in Neovim.

local M = {}

local client = require("ask-openai.voiced.client")
local paste = require("ask-openai.voiced.paste")
local log = require("devtools.logs.logger").universal()

--- Arm paste mode by capturing the currently-focused window's buffer and cursor.
--- The next final transcription is inserted at this exact spot.
function arm_paste_mode()
    if paste.arm() then
        log:info("voiced: paste mode armed")
        print("[voiced] paste mode armed - speak (PTT) and the final transcript will be inserted here")
    end
end

local function on_transcription(event)
    local text = event.text or ""
    local is_final = event.final or false
    log:info("voiced transcription" .. (is_final and " [final]" or ""), text)

    -- If paste mode is armed, route the FINAL transcript into the buffer.
    if is_final and paste.is_armed() then
        if text ~= "" then
            paste.paste(text)
        end
        return
    end

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

    vim.api.nvim_create_user_command("VoicedPaste", function()
        arm_paste_mode()
    end, { desc = "Arm paste mode: next final transcription is inserted at the cursor" })

    vim.api.nvim_create_user_command("VoicedPasteCancel", function()
        paste.cancel()
        log:info("voiced: paste mode cancelled")
        print("[voiced] paste mode cancelled")
    end, { desc = "Cancel armed paste mode" })

    -- <leader>vp arms paste mode. The next FINAL transcription (i.e. after you
    -- release PTT) is inserted at the cursor captured at arm time, then paste
    -- mode disarms. Live (final=false) streamed updates are ignored.
    vim.keymap.set("n", "<leader>vp", function()
        arm_paste_mode()
    end, { desc = "Voiced: paste next transcription into buffer" })
end

return M
