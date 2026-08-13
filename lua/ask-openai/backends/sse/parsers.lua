local log = require("devtools.logs.logger"):universal()

-- logic for parsing SSEs from all completion backends

---@class SseFieldsResult
---@field content string  -- The content chunk from this SSE
---@field done boolean  -- Whether this is the final SSE (generation complete)
---@field finish_reason? string  -- Reason why generation stopped (e.g., "stop", "length", "eos")
---@field reasoning_content? string -- Reasoning/thinking content if available
---@field prob? number -- Probability of the selected token

function get_probs(choice)
    -- PRN parse logprobs
    -- * post_sampling_probs = TRUE =>
    --
    --     material diff is returning probability (0 to 1)
    --       also truncates any tokens that round to zero probability
    --       whereas below logprobs will show those
    --
    --     choices[1].logprobs.content.{prob,top_probs}
    --     top_probs[1].prob
    --
    --     logprobs = {
    --       content = { {
    --           bytes = { 32, 105, 110, 115, 101, 114, 116 },
    --           id = 10898,
    --           prob = 0.95149838924408,
    --           token = " insert",
    --           top_probs = { {
    --               bytes = { 32, 105, 110, 115, 101, 114, 116 },
    --               id = 10898,
    --               prob = 0.95149838924408,
    --               token = " insert"
    --             }, {
    --               bytes = { 32, 97, 100, 100 },
    --               id = 1147,
    --               prob = 0.048501636832952,
    --               token = " add"
    --             } }
    --         } }
    --     }
    --
    --
    -- * post_sampling_probs = FALSE =>
    --
    --     material diff is returning logits (IIAC -infinity to 0)
    --        e^0 == 1 (100% probability)
    --
    --     choices[1].logprobs.content.{logprob,top_logprobs}
    --     top_logprobs[1].logprob
    --
    --     logprobs = {
    --         content = { {
    --             bytes = { 32, 105, 110, 115, 101, 114, 116 },
    --             id = 10898,
    --             logprob = -0.020740794017911,
    --             token = " insert",
    --             top_logprobs = { {
    --                 bytes = { 32, 105, 110, 115, 101, 114, 116 },
    --                 id = 10898,
    --                 logprob = -0.020740794017911,
    --                 token = " insert"
    --               }, {
    --                 bytes = { 32, 97, 100, 100 },
    --                 id = 1147,
    --                 logprob = -4.3584332466125,
    --                 token = " add"
    --               }, {
    --                 bytes = { 32, 102, 105, 108, 108 },
    --                 id = 6954,
    --                 logprob = -5.1742367744446,
    --                 token = " fill"
    --               }, {
    --                 bytes = { 32, 115, 117, 103, 103, 101, 115, 116 },
    --                 id = 6108,
    --                 logprob = -6.732141494751,
    --                 token = " suggest"
    --               }, {
    --                 bytes = { 32, 114, 101, 112, 108, 97, 99, 101 },
    --                 id = 13284,
    --                 logprob = -7.2061409950256,
    --                 token = " replace"
    --               } }
    --           } }
    --       }
    if not choice.logprobs
        or not choice.logprobs.content then
        return nil
    end
    logprob_content = choice.logprobs.content[1]

    if logprob_content.logprob ~= nil and logprob_content.logprob ~= vim.NIL then
        log:error("raw logprob is not supported, submit post_sampling_probs=true to receive probabilities directly")
        return nil
    end

    -- FYI for now I am only returning probability of selected token
    --  TODO expand to include probs for all tokens returned (if specified then # == top_logprobs count)
    local selected_token_prob = logprob_content.prob
    return selected_token_prob
end

---@param value string|vim.NIL|nil
---@return string
local function empty_for_nil(value)
    if value == nil then
        return ""
    end
    if value == vim.NIL then
        return ""
    end
    ---@cast value string -- tell type checker to shut up
    return value
end

local function vim_NIL_to_nil(value)
    if value == vim.NIL then
        return nil
    end
    return value
end

---@param sse LlamaServerChatCompletionSSE
---@return SseFieldsResult
function parse_sse_v1_chat_completions(sse)
    if not sse.choices or not sse.choices[1] then
        log:error("SSE is missing choices", sse)
        -- leave as hard stop error b/c I don't think this ever happens... but error will help me figure out if it does!
        -- this would be for chat completions endpoint only... that's part of expectation already in calling this parse_sse_v1_chat_completions
        -- and right now I only use this for predictions
        error("SSE is missing choices - I don't think this ever happens so if it does... then raise hard error")
    end

    local first_choice = sse.choices[1]
    local delta = first_choice.delta
    if delta == nil then
        -- TODO get rid of this log if never happens and/or doesn't matter
        log:info("case with no delta on a chat completions SSE - I think this does happen toward end of trace, right? and maybe at first")
        error("unexpected missing delta on a chat completions SSE")
    end

    local prob = get_probs(first_choice)
    -- log:info("prob", prob)

    local finish_reason = vim_NIL_to_nil(first_choice.finish_reason)

    return {
        -- content == vim.NIL => first response has `content: null` b/c it is setting the role to asssistant
        --   - likely due to roles/channels token(s) in harmony parser (among others)
        -- content == nil
        --   - 2+ SSEs are for reasoning and use reasoning_content until thinking is complete (these don't even set the content field, so it's nil in this case)
        content = empty_for_nil(delta.content),

        -- FYI I have yet to seel reasoning_content come back with vim.NIL (and maybe not even nil?)
        reasoning_content = empty_for_nil(delta.reasoning_content),

        -- FYI finish_reason is vim.NIL until it is set (end of completion)
        finish_reason = finish_reason,
        done = finish_reason ~= nil,

        prob = prob,
    }
end

---@param sse LlamaServerRawCompletionSSE
---@return SseFieldsResult
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
    log:info("raw sse", sse)

    return {
        content           = empty_for_nil(sse.content),
        done              = sse.stop == true, -- ensure always a boolean even if stop were nil

        -- FYI I have not encountered sse.stop_type == vim.NIL, doesn't hurt to check
        finish_reason     = vim_NIL_to_nil(sse.stop_type),

        -- unused for this endpoint, set default values:
        reasoning_content = "",
        prob              = nil,
    }
end
