local log = require("devtools.logs.logger"):universal()

-- logic for parsing SSEs from all completion backends

---@param sse OpenAIChatCompletionChunk
function parse_sse_oai_chat_completions(sse)
    local content = ""
    local reasoning_content = ""
    local done = false
    local finish_reason = nil
    if sse.choices and sse.choices[1] then
        local first_choice = sse.choices[1]
        content = first_choice.delta.content
        if content == nil or content == vim.NIL then
            -- content == vim.NIL => with llama-server the first response is content: null b/c it is setting the role to asssistant (maybe to do with roles/channels in harmony parser)... doesn't matter, just ignore it
            --    vim.NIL == "content": null (in the JSON)
            -- content == nil => then 2+ SSEs are for reasoning and use reasoning_content until thinking is complete (these don't even set the content field, so it's nil in this case)
            --    skip these too
            content = ""
        end
        -- llama-server's /v1/chat/comppletions endpoint uses delta.reasoning_content
        reasoning_content = first_choice.delta.reasoning_content
        finish_reason = first_choice.finish_reason
        done = finish_reason ~= nil and finish_reason ~= vim.NIL -- vim.NIL == JSON null
    end
    return content, done, finish_reason, reasoning_content
end

function parse_sse_llamacpp_completions(sse)
    -- FYI response_fields limits fields per SSE...
    --    I set it to stop prompt and generation_settings on final SSE

    -- {"index":0,"content":"\",","tokens":[497],"stop":false,"id_slot":-1,"tokens_predicted":14,"tokens_evaluated":1963}
    -- stop: true => a few fields (it returns entire prompt too so it's huge!... maybe skip logging the prompt field?)
    -- "truncated": false,
    -- "stop_type": "eos",
    -- "stopping_word": "", -- FYI this is for last token that stopped generation (if applicable) ... and IIRC it does not get added into the content
    -- log:info("sse /completions", vim.inspect(sse))

    -- TWO ways to use llama-server's /completions
    --   non-raw - can't recall using this on anything material - this might have reasoning parsers but I would prefer use chat completions for that
    --   raw - I've used this for gptoss and qwen2.5coder - I could build a reasoning parser myself but it would be a layer above this
    --   TLDR not likely to ever use reasoning with this endpoint (unless I need manual parsing)
    --
    -- Going forward, use /completions for RAW only
    -- use /v1/chat/completions for any chat template conversations
    return sse.content, sse.stop, sse.stop_type
end
