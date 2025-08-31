-- logic for parsing SSEs from all completion backends

function parse_sse_oai_chat_completions(sse)
    content = ""
    if sse.choices and sse.choices[1] then
        content = sse.choices[1].delta.content
        if content == vim.NIL then
            -- TODO fix llama-server + gpt-oss on chat/completions
            --   streaming response streams low level tokens including channel!
            --   and the first response's content is vim.NIL (seems to indicate the template issue too)
            error("content: " .. tostring(content) .. " is vim.NIL, WHY?!")
            content = ""
        end
        reasoning = sse.choices[1].delta.reasoning
        -- TODO SHOW THINKING!!!?
    end
    done = sse.finish_reason ~= nil -- or "null"? or vim.NIL
    finish_reason = sse.finish_reason
    return content, done, finish_reason, reasoning

    -- * gpt-oss:20b chat/completions ollama example:
    -- reasoning/thinking content (full message, all fields):
    --   {"id":"chatcmpl-900","object":"chat.completion.chunk","created":1754453131,"model":"gpt-oss:20b","system_fingerprint":"fp_ollama",
    --     "choices":[{"index":0,"delta":{"role":"assistant","content":"","reasoning":"?"},"finish_reason":null}]}
    -- content:
    --   "choices":[{"index":0,"delta":{"role":"assistant","content":" }"},"finish_reason":null}]}
    --   "choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":"stop"}]}
end

function parse_sse_ollama_chat(sse)
    -- vim.print(sse)
    --   created_at = "2025-08-06T03:41:18.754207861Z",
    --   done = true,
    --   done_reason = "load",
    --   message = {
    --     content = "",
    --     role = "assistant"
    --   },

    -- it has "thinking"!
    -- gpt-oss:
    --   "message":{"role":"assistant","content":"","thinking":"   "},"done":false}

    message = ""
    if sse.message then
        message = sse.message.content
    end
    return message, sse.done, sse.done_reason
end

function parse_llama_cpp_server(sse)
    -- FYI response_fields limits fields per SSE...
    --    I set it to stop prompt and generation_settings on final SSE

    -- {"index":0,"content":"\",","tokens":[497],"stop":false,"id_slot":-1,"tokens_predicted":14,"tokens_evaluated":1963}
    -- stop: true => a few fields (it returns entire prompt too so it's huge!... maybe skip logging the prompt field?)
    -- "truncated": false,
    -- "stop_type": "eos",
    -- "stopping_word": "", -- TODO what is this for?
    return sse.content, sse.content, sse.stop_type
end

function parse_ollama_api_generate(sse)
    -- *** examples /api/generate:
    --    {"model":"qwen2.5-coder:3b","created_at":"2025-01-26T11:24:56.1915236Z","response":"\n","done":false}
    --  done example:
    --    {"model":"qwen2.5-coder:3b","created_at":"2025-01-26T11:24:56.2800621Z","response":"","done":true,"done_reason":"stop","total_duration":131193100,"load_duration":16550700,"prompt_eval_count":19,"prompt_eval_duration":5000000,"eval_count":12,"eval_duration":106000000}

    return sse.response, sse.done, sse.done_reason
end
