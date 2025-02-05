
    local function process_sse(data)
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
                event_json = ss_event:sub(7)
            end
            local success, parsed = pcall(vim.json.decode, event_json)

            -- *** /v1/completions
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

                -- -- *** ollama format for /api/generate, examples:
                -- --    {"model":"qwen2.5-coder:3b","created_at":"2025-01-26T11:24:56.1915236Z","response":"\n","done":false}
                -- --  done example:
                -- --    {"model":"qwen2.5-coder:3b","created_at":"2025-01-26T11:24:56.2800621Z","response":"","done":true,"done_reason":"stop","total_duration":131193100,"load_duration":16550700,"prompt_eval_count":19,"prompt_eval_duration":5000000,"eval_count":12,"eval_duration":106000000}
                -- if success and parsed and parsed.response then
                --     if parsed.done then
                --         local done_reason = parsed.done_reason
                --         done = true
                --         if done_reason ~= "stop" then
                --             log:warn("WARN - unexpected /api/generate done_reason: ", done_reason, " do you need to handle this too?")
                --             -- ok for now to continue too
                --         end
                --     end
                --     chunk = (chunk or "") .. parsed.response
            else
                log:warn("SSE json parse failed for ss_event: ", ss_event)
            end
        end
        return chunk, done
    end
