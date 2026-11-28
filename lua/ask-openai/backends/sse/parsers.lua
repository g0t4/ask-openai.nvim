local log = require("devtools.logs.logger"):universal()
local values = require("ask-openai.helpers.values")
local response_reasoning = require("ask-openai.backends.response_reasoning")
local response_metadata = require("ask-openai.backends.response_metadata")
local SSEWrapped = require("ask-openai.agents.sse_wrapped")
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

---@param sse_wrapped SSEWrapped
---@return SseFieldsResult? -- nil == no content/reasoning/finish_reason
function parse_sse_v1_chat_completions(sse_wrapped)
    if sse_wrapped:has_error() then
        -- error examples:
        -- { error = { code = 503, message = "Loading model", type = "unavailable_error" } }
        return nil
    end
    if sse_wrapped:no_choices() then
        -- skip if no choices (can happen on SSEs at end with timing)
        -- if it happens elsewhere just skip it for now
        -- PRN consider logging if not an timings SSE where this is known to happen
        return nil
    end

    local first_choice = sse_wrapped:first_choice()
    local delta = first_choice.delta
    if delta == nil then
        -- TODO get rid of this log if never happens and/or doesn't matter
        log:info("case with no delta on a chat completions SSE - I think this does happen toward end of trace, right? and maybe at first")
        error("unexpected missing delta on a chat completions SSE")
    end

    local prob = get_probs(first_choice)
    -- log:info("prob", prob)

    local finish_reason = sse_wrapped:finish_reason()

    return {
        -- content == vim.NIL => first response has `content: null` b/c it is setting the role to asssistant
        --   - likely due to roles/channels token(s) in harmony parser (among others)
        -- content == nil
        --   - 2+ SSEs are for reasoning and use reasoning_content until thinking is complete (these don't even set the content field, so it's nil in this case)
        content = values.empty_for_nil(delta.content),

        reasoning_content = values.empty_for_nil(response_reasoning.get_content(delta)),

        -- FYI finish_reason is vim.NIL until it is set (end of completion)
        finish_reason = finish_reason,
        done = sse_wrapped:is_finished(),

        prob = prob,
    }
end

---@param sse_wrapped SSEWrapped
---@return SseFieldsResult
function parse_sse_llamacpp_completions(sse_wrapped)
    ---@cast sse_wrapped.sse_parsed LlamaServerRawCompletionSSE
    local sse = sse_wrapped.sse_parsed
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
    return {
        content           = values.empty_for_nil(sse.content),
        done              = sse.stop == true, -- ensure always a boolean even if stop were nil

        -- already nil_ified by the SSEWrapped ctor
        finish_reason     = sse.stop_type,

        -- unused for this endpoint, set default values:
        reasoning_content = "",
        prob              = nil,
    }
end
