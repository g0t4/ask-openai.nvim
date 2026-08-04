local log = require("devtools.logs.logger").universal()
local api = require("ask-openai.api")
local local_share = require("ask-openai.config.local_share")
local models = require("ask-openai.config.models")
local gptoss_tokenizer = require("ask-openai.backends.models.gptoss.tokenizer")

local M = {}

---@param request_body table
---@param recommended table - use as defaults, IOTW start with this table and overlay changes from request_body table
---@return table merged body
function default_to_recommended(request_body, recommended)
    -- rightmost wins
    local merged = vim.tbl_deep_extend("force", recommended, request_body or {})
    -- log:luaify_trace("merged request body: ", merged)
    return merged
end

---@param request_body table
local function throw_if_no_messages(request_body)
    if request_body.messages == nil then
        error("messages are required for gpt-oss chat")
    end
end

---@param request_body table
---@param reasoning_level string
---@return table
local function set_enable_thinking(request_body, reasoning_level)
    request_body.chat_template_kwargs = request_body.chat_template_kwargs or {}
    request_body.chat_template_kwargs.enable_thinking = reasoning_level ~= models.THINKING_OFF
    return request_body
end

---@param request_body table
---@param context CurrentContext
---@return table
function M.new_gptoss_chat_body_llama_server(request_body, context, reasoning_level)
    throw_if_no_messages(request_body)


    local max_tokens = gptoss_tokenizer.get_gptoss_max_tokens_for_level(reasoning_level)

    local recommended = {

        -- We recommend sampling with temperature=1.0 and top_p=1.0.
        --   https://github.com/openai/gpt-oss?tab=readme-ov-file#recommended-sampling-parameters
        temperature = 1.0,
        top_p = 1.0,

        chat_template_kwargs = {
            -- TODO don't add if off?
            reasoning_effort = reasoning_level,
        },
        max_tokens = max_tokens,

        -- verbose = true, -- add __verbose
    }
    return default_to_recommended(request_body, recommended)
end

---@param request_body table
---@param context CurrentContext
---@return table
function M.new_deepseek4flash_chat_body_llama_server(request_body, context, effort)
    throw_if_no_messages(request_body)

    local recommended = {

        -- https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash#how-to-run-locally
        -- For local deployment, we recommend setting the sampling parameters to temperature = 1.0, top_p = 1.0.
        -- For the Think Max reasoning mode, we recommend setting the context window to at least 384K tokens.       --

        temperature = 1.0,
        top_p = 0.95, -- flash-0731 recommends 0.95 for agent use ase, otherwise 1.0
        -- top_p = 1.0,

        max_tokens = 393216, -- 384K suggested context size so yeah that works for tokens per turn :) ... I hope

        -- llama.cpp's jinja featuers to try:
        -- - supports system prompt addition (concatenates into one system prompt for you, can have multiple too)
        -- - TODO try response_format_template? is this how people provide a template to follow i.e. reasoning but for final response?

        -- jinja template not included in the model:
        --  BTW currently llama-sever does not start w/ the template it bundles for deepseek-v4-flash-0731
        --   probably because there is no template bundled in the upstream model itself?
        --   uses some v3.2/v4 template?
        --
        --  /home/wes/repos/github/ggml-org/llama.cpp/build/bin/llama-server \
        --     -hf ggml-org/DeepSeek-V4-Flash-0731-GGUF \
        --     --chat-template-file ~/repos/github/ggml-org/llama.cpp/models/templates/deepseek-ai-DeepSeek-V4-Flash-0731.jinja
        --
        -- reasoning levels
        --   0731 => https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash-0731#chat-template
        --   * levels: non-think, low, high, max
        --   sounds like there is a special system prompt for max too?
        --   and no official jinja?
        --
        -- preview => https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash#instruct-model
        --   levels: non-think, high, max

        verbose = true, -- add __verbose

        chat_template_kwargs = {}
    }

    local efforts = models.DEEPSEEK_REASONING_EFFORT
    if effort == efforts.OFF then
        recommended.chat_template_kwargs.enable_thinking = false
    elseif effort == efforts.HIGH
        or effort == efforts.MAX then
        recommended.chat_template_kwargs.reasoning_effort = effort
        -- else "low" => default w/o high/max system prompt mods
    end

    return default_to_recommended(request_body, recommended)
end

---@param request_body table
---@param context CurrentContext
---@return table
function M.new_glm47flash_chat_body_llama_server(request_body, context, reasoning_level)
    throw_if_no_messages(request_body)
    -- FYI RECOMMMENDS: https://huggingface.co/zai-org/GLM-4.7-Flash#evaluation-parameters
    --   TODO! recommends preserved thinking mode for terminal bench (similar to what my intent here is)
    --     TODO https://docs.z.ai/guides/capabilities/thinking-mode

    -- TODO try out default recommends too? this is where having my own evals could help!
    local recommends_default = {
        temperature = 1.0,
        top_p       = 0.95,
        max_tokens  = 131072,
    }
    local recommends_for_terminal_bench_swe = {
        temperature = 0.7,
        top_p = 1.0,
        -- max_tokens = 16384, -- PRN adjust for my own taste? this seems mostly reasonable unless generating a huge file?
    }

    local body = default_to_recommended(request_body, recommends_for_terminal_bench_swe)
    return set_enable_thinking(body, reasoning_level)
end

---@param request_body table
---@param context CurrentContext
---@return table
function M.new_gemma4_chat_body_llama_server(request_body, context, reasoning_level)
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
    local body = default_to_recommended(request_body, recommended)
    return set_enable_thinking(body, reasoning_level)
end

---@param request_body table
---@param context CurrentContext
---@return table
function M.new_qwen3coder_llama_server_chat_body(request_body, context, reasoning_level) -- this is a duplicate
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
    local body = default_to_recommended(request_body, recommended)
    return set_enable_thinking(body, reasoning_level)
end

return M
