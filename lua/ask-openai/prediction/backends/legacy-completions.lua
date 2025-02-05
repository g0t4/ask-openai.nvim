local M = {}
local log = require("ask-openai.prediction.logger").predictions()

local function body_for(prefix, suffix)
    local body = {

        model = "fim_qwen:7b-instruct-q8_0", -- qwen2.5-coder, see Modelfile

        -- *** deepseek-coder-v2 (MOE 16b model)
        -- TODO retry w/ truncate fixes (ensure logs show not truncating)
        -- model = "deepseek-coder-v2:16b-lite-instruct-q8_0",
        --   prompt has template w/ PSM!
        --      ollama show --template deepseek-coder-v2:16b-lite-instruct-q8_0

        -- *** codellama
        -- TODO retry w/ truncate fixes (ensure logs show not truncating)
        -- model = "codellama:7b-code-q8_0", -- `code` and `python` have FIM, `instruct` does not
        -- keeps generating <EOT> in output ... is the template wrong?
        --    - PRN add to stop parameter?
        -- btw => codellama:-code uses: <PRE> -- calculator\nlocal M = {}\n\nfunction M.add(a, b)\n    return a + b\nend1 <SUF>1\n\n\n\nreturn M <MID>

        -- /v1/completions uses Template (no raw override)
        -- - https://github.com/ollama/ollama/blob/main/docs/template.md#example-fill-in-middle
        prompt = prefix,
        suffix = suffix,

        stream = true,
        max_tokens = 200,

        -- TODO temperature, top_p, etc => (see notes for more)
    }

    return vim.json.encode(body)
end

function M.build_request(prefix, suffix)
    local options = {
        command = "curl",
        args = {
            "-fsSL",
            "--no-buffer", -- curl seems to be the culprit... w/o this it batches (test w/ `curl *` vs `curl * | cat` and you will see difference)
            "-X", "POST",
            "http://ollama:11434/v1/completions", -- TODO pass in api base_url (via config)
            "-H", "Content-Type: application/json",
            "-d", body_for(prefix, suffix)
        },
    }
    return options
end

function M.process_sse(data)
    -- TODO tests of parsing?
    -- SSE = Server-Sent Event
    -- split on lines first (each SSE can have 0+ "event" - one per line)

    -- FYI use nil to indicate nothing in the SSE... vs empty line which is a valid thingy right?
    local chunk = nil -- combine all chunks into one string and check for done
    local done = false
    for ss_event in data:gmatch("[^\r\n]+") do
        if ss_event:match("^data:%s*%[DONE%]$") then
            -- done, courtesy last event... mostly ignore b/c finish_reason already comes on the prior SSE
            return chunk, true
        end

        --  strip leading "data: " (if present)
        local event_json = ss_event
        if ss_event:sub(1, 6) == "data: " then
            -- ollama /api/generate doesn't prefix each SSE with 'data: '
            -- IIRC /v1/completions doesn't do this
            event_json = ss_event:sub(7)
        end
        local success, parsed = pcall(vim.json.decode, event_json)

        if success and parsed.choices and parsed.choices[1] and parsed.choices[1].text then
            local choice = parsed.choices[1]
            local text = choice.text
            if choice.finish_reason == "stop" then
                done = true
            elseif choice.finish_reason == "length" then
                done = true
            elseif choice.finish_reason ~= vim.NIL then
                log:warn("WARN - unexpected /v1/completions finish_reason: ", choice.finish_reason, " do you need to handle this too?")
                -- ok for now to continue too
                done = true
            end
            chunk = (chunk or "") .. text
        else
            log:warn("SSE json parse failed for ss_event: ", ss_event)
        end
    end
    return chunk, done
end

return M
