local log = require("ask-openai.logs.logger").predictions()
local api = require("ask-openai.api")
local local_share = require("ask-openai.config.local_share")
local gptoss_tokenizer = require("ask-openai.backends.models.gptoss.tokenizer")

local M = {}

function default_to_recommended(request_body, recommended)
    -- rightmost wins
    local merged = vim.tbl_deep_extend("force", recommended, request_body or {})
    -- log:luaify_trace("merged request body: ", merged)
    return merged
end

local function throw_if_no_messages(request_body)
    if request_body.messages == nil then
        error("messages are required for gpt-oss chat")
    end
end

---@param request_body table
---@param context CurrentContext
---@return table
function M.new_gptoss_chat_body_llama_server(request_body, context)
    throw_if_no_messages(request_body)

    local level = context.includes:get_reasoning_level()
        or api.get_rewrite_reasoning_level()

    local max_tokens = gptoss_tokenizer.get_gptoss_max_tokens_for_level(level)

    local recommended = {

        -- We recommend sampling with temperature=1.0 and top_p=1.0.
        --   https://github.com/openai/gpt-oss?tab=readme-ov-file#recommended-sampling-parameters
        temperature = 1.0,
        top_p = 1.0,

        chat_template_kwargs = {
            reasoning_effort = level,
        },
        max_tokens = max_tokens,

        -- verbose = true, -- * my build of llama-server will one-off add __verbose if verbose is set on body of request!

    }
    return default_to_recommended(request_body, recommended)
end

function M.new_gemma4_chat_body_llama_server(request_body, context)
    throw_if_no_messages(request_body)
    --  Thinking config: https://huggingface.co/google/gemma-4-26B-A4B#2-thinking-mode-configuration
    --    Thinking is enabled by including the <|think|> token at the start of the system prompt. To disable thinking, remove the token.
    --      TODO does template have an option that llama-server can pass from request body... or that it llama-server hard codes?
    --        TODO does llama-server fully support gemma4 reasoning (thinking tags/tokens?) that might be why I see <thought> periodically!
    --    Standard Generation: When thinking is enabled, the model will output its internal reasoning followed by the final answer using this structure:
    --      <|channel>thought\n[Internal reasoning]<channel|>
    --    FYI Disabled Thinking Behavior: For all models except for the E2B and E4B variants, if thinking is disabled, the model will still generate the tags but with an empty thought block:
    --      <|channel>thought\n<channel|>[Final answer]
    --      TODO should I strip the tags then? or does llama-server handle this? yet?

    local recommended = {
        -- recommendations:
        --  sampling params:  https://huggingface.co/google/gemma-4-26B-A4B#1-sampling-parameters
        temperature = 1.0,
        top_p = 0.95,
        top_k = 64,
    }
    return default_to_recommended(request_body, recommended)
end

function M.new_qwen3coder_llama_server_chat_body(request_body, context) -- this is a duplicate
    throw_if_no_messages(request_body)

    local recommended = {
        -- official recommended settings (for transformers):
        -- https://huggingface.co/Qwen/Qwen3-Coder-480B-A35B-Instruct/blob/main/generation_config.json
        --   "repetition_penalty": 1.05,
        --   "temperature": 0.7,
        --   "top_p": 0.8,
        --   "top_k": 20
        repeat_penalty = 1.05,
        temperature = 0.7,
        top_p = 0.8,
        top_k = 20,
        --  FYI I inlined these values into predictions handler, it's not using chat completions endpoint so not gonna conflate the two here
    }
    return default_to_recommended(request_body, recommended)
end

function M.new_qwen25coder_ollama_body(request_body)
    -- get values from rewrite/ask/predictions
    -- PRN I should run some tests too, I never optimized using 2.5-Coder!
    --   keep in mind it had both base and instruct variants
end

return M
