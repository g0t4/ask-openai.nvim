-- logic for parsing SSEs from all completion backends

function parse_sse_oai_chat_completions(sse)
    content = ""
    if sse.choices and sse.choices[1] then
        content = sse.choices[1].delta.content
        if content == nil or content == vim.NIL then
            -- content == vim.NIL => with llama-server the first response is content: null b/c it is setting the role to asssistant (maybe to do with roles/channels in harmony parser)... doesn't matter, just ignore it
            --    vim.NIL == "content": null (in the JSON)
            -- content == nil => then 2+ SSEs are for reasoning and use reasoning_content until thinking is complete (these don't even set the content field, so it's nil in this case)
            --    skip these too
            content = ""
        end
        -- llama-server's /v1/chat/comppletions endpoint uses delta.reasoning_content
        -- ollama's uses delta.reasoning
        reasoning_content = sse.choices[1].delta.reasoning or sse.choices[1].delta.reasoning_content
    end
    done = sse.finish_reason ~= nil -- or "null"? or vim.NIL
    finish_reason = sse.finish_reason
    return content, done, finish_reason, reasoning_content
end

function parse_sse_ollama_chat(sse)
    -- vim.print(sse)
    --   created_at = "2025-08-06T03:41:18.754207861Z",
    --   done = true,
    --   done_reason = "load",
    --   message = TxChatMessage:assistant("")

    -- it has "thinking"!
    -- gpt-oss:
    --   "message":{"role":"assistant","content":"","thinking":"   "},"done":false}

    message = ""
    if sse.message then
        message = sse.message.content
    end
    -- TODO reasoning_content
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

    -- TODO reasoning_content
    return sse.content, sse.content, sse.stop_type
end

function parse_ollama_api_generate(sse)
    -- *** examples /api/generate:
    --    {"model":"qwen2.5-coder:3b","created_at":"2025-01-26T11:24:56.1915236Z","response":"\n","done":false}
    --  done example:
    --    {"model":"qwen2.5-coder:3b","created_at":"2025-01-26T11:24:56.2800621Z","response":"","done":true,"done_reason":"stop","total_duration":131193100,"load_duration":16550700,"prompt_eval_count":19,"prompt_eval_duration":5000000,"eval_count":12,"eval_duration":106000000}

    -- TODO reasoning_content
    return sse.response, sse.done, sse.done_reason
end
