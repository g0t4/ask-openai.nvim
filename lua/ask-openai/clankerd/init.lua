--- ask-openai clankerd module: connects to the clankerd daemon and surfaces
--- its agent responses and status in Neovim.

local M = {}

local client = require("ask-openai.clankerd.client")
local log = require("devtools.logs.logger").universal()

local function on_transcription(event)
    local text = event.text or ""
    local is_final = event.final or false
    log:info("clankerd transcription" .. (is_final and " [final]" or ""), text)
    local prefix = is_final and "[clankerd ✓] " or "[clankerd] "
    print(prefix .. text)
end

local function on_agent_response(event)
    local text = event.text or ""
    log:info("clankerd agent_response", text)
    print("[clankerd] " .. text)
end

local function on_status(event)
    log:info("clankerd status", event.state)
    print("[clankerd] status: " .. (event.state or "unknown"))
end

function M.setup()
    client.set_handler("transcription", on_transcription)
    client.set_handler("agent_response", on_agent_response)
    client.set_handler("status", on_status)
    client.set_handler("pong", function(event)
        log:info("clankerd pong", event.status)
    end)
    client.set_handler("error", function(event)
        log:info("clankerd error", event.message)
    end)

    client.connect()

    vim.api.nvim_create_user_command("ClankerdStatus", function()
        client.send({ type = "ping" })
    end, { desc = "Ping the clankerd daemon" })

    vim.api.nvim_create_user_command("ClankerdMessage", function(args)
        client.send({ type = "message", text = args.args, final = true })
    end, { nargs = 1, desc = "Send a message to the clankerd daemon" })
end

return M
