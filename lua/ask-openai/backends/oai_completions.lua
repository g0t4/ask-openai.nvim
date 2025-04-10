local curl = require("ask-openai.backends.curl_streaming")
local log = require("ask-openai.prediction.logger").predictions()

-- aka "legacy" completions endpoint
-- no chat history concept
--   good for single turn requests
--   can easily be used for back and forth if you are summarizing previous messages into the next prompt
-- raw prompt typically is reason to use this
--   i.e. FIM
--       TODO port my FIM to use this too, great way to test it and ensure its flexible
-- can get confusing if not "raw" and the backend applies templates that are shipped w/ the model...
--   you can use that just make sure you understand it and appropriately build the request body

-- *** input parameters supported /v1/chat/completions
-- FYI parameters should mostly be set by end users of this backend abstraction
--   obviously "stream: true" is universal here
--   backend can enforce required params and validate optional params, if needed
--
-- prompt (entire message)
-- model
-- max_tokens
-- suffix (IIRC not avail with vllm, ollama uses for FIM except if raw=true, )
-- stop
-- stream
-- seed, temperature, top_p, n, frequency_penalty, presence_penalty
--

local M = {}
_G.PLAIN_FIND = true
function M.curl_for(body, base_url, frontend)
    local url = base_url .. "/v1/completions"
    return curl.reusable_curl_seam(body, url, frontend, M.sse_to_chunk)
end

-- *** output shape
--   FYI largely the same as for /v1/chat/completions, except the generated text
--  created, id, model, object, system_fingerprint, usage
--  choices
--    finish_reason: string  # vllm seems to use stop_reason (see below)
--    index: integer
--    logprobs: obj/null
--    text: string    (*** this is the only difference vs chat)

-- *** vllm /v1/completions responses:
--  middle completion:
--   {"id":"cmpl-eec6b2c11daf423282bbc9b64acc8144","object":"text_completion","created":1741824039,"model":"Qwen/Qwen2.5-Coder-3B","choices":[{"index":0,"text":"ob","logprobs":null,"finish_reason":null,"stop_reason":null}],"usage":null}
--
--  final completion:
--   {"id":"cmpl-06be557c45c24e458ea2e36d436faf60","object":"text_completion","created":1741823318,"model":"Qwen/Qwen2.5-Coder-3B","choices":[{"index":0,"text":" and","logprobs":null,"finish_reason":"length","stop_reason":null}],"usage":null}
--    pretty print with vim:
--    :Dump(vim.json.decode('{"id":"cmpl-06be557c45c24e458ea2e36d436faf60","object":"text_completion","created":1741823318,"model":"Qwen/Qwen2.5-Coder-3B","choices":[{"index":0,"text":" and","logprobs":null,"finish_reason":"length","stop_reason":null}],"usage":null}')
-- {
--   choices = { {
--       finish_reason = "length",
--       index = 0,
--       logprobs = vim.NIL,
--       stop_reason = vim.NIL,
--       text = " and"
--     } },
--   created = 1741823318,
--   id = "cmpl-06be557c45c24e458ea2e36d436faf60",
--   model = "Qwen/Qwen2.5-Coder-3B",
--   object = "text_completion",
--   usage = vim.NIL
-- }
-- TODO does vllm have both finish_reason and stop_reason?


--- @param data string
--- @return string text|nil, boolean|nil is_done, string|nil finish_reason
function M.sse_to_chunk(data)
    -- SSE = Server-Sent Event
    -- split on lines first (each SSE can have 0+ "event" - one per line)

    local chunk = nil -- combine all chunks into one string and check for done
    local done = false
    local finish_reason = nil
    for ss_event in data:gmatch("[^\r\n]+") do
        if ss_event:match("^data:%s*%[DONE%]$") then
            -- done, courtesy last event... mostly ignore b/c finish_reason already comes on the prior SSE
            return chunk, true
        end

        --  strip leading "data: " (if present)
        local event_json = ss_event
        if ss_event:sub(1, 6) == "data: " then
            event_json = ss_event:sub(7)
        end
        local success, parsed = pcall(vim.json.decode, event_json)

        if success and parsed and parsed.choices and parsed.choices[1] then
            local first_choice = parsed.choices[1]
            finish_reason = first_choice.finish_reason
            if finish_reason ~= nil and finish_reason ~= vim.NIL then
                done = true
                if finish_reason ~= "stop" and finish_reason ~= "length" then
                    log:warn("WARN - unexpected finish_reason: ", finish_reason, " do you need to handle this too?")
                end
            end

            -- * differs vs /v1/chat/completions endpoint
            if first_choice.text == nil then
                log:warn("WARN - unexpected, no choice in completion, do you need to add special logic to handle this?")
            else
                chunk = (chunk or "") .. first_choice.text
            end

        else
            log:warn("SSE json parse failed for ss_event: ", ss_event)
        end
    end
    return chunk, done, finish_reason
end

return M
