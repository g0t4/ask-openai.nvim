local log = require("ask-openai.logs.logger").predictions()

local M = {}

function default_to_recommended(request_body, recommended)
    -- rightmost wins
    local merged = vim.tbl_deep_extend("force", recommended, request_body or {})
    log:info("merged request body: " .. vim.inspect(merged))
    return merged
end

local function throw_if_no_messages(request_body)
    if request_body.messages == nil then
        error("messages are required for gpt-oss chat")
    end
end


function M.new_gptoss_chat_body_llama_server(request_body)
    throw_if_no_messages(request_body)

    local recommended = {
        -- https://huggingface.co/openai/gpt-oss-20b/blob/main/generation_config.json
        --   "bos_token_id": 199998,
        --   "do_sample": true,
        --   "eos_token_id": [
        --     200002,
        --     199999,
        --     200012
        --   ],
        --   "pad_token_id": 199999,
        --   "transformers_version": "4.55.0.dev0"
        bos_token_id = 199998,
        do_sample = true,
        eos_token_id = { 200002, 199999, 200012 },
        pad_token_id = 199999,

        -- gh repo has more recommends
        --   We recommend sampling with temperature=1.0 and top_p=1.0.
        --   https://github.com/openai/gpt-oss?tab=readme-ov-file#recommended-sampling-parameters
        --
        temperature = 1.0,
        top_p = 1.0,


        -- TODO test/validate these settings
        -- TODO also adjust per circumstance? (pass to override then)
    }
    return default_to_recommended(request_body, recommended)
end

function M.new_qwen3coder_llama_server_chat_body(request_body) -- this is a duplicate
    throw_if_no_messages(request_body)

    local recommended = {
        -- official recommended settings
        -- https://huggingface.co/Qwen/Qwen3-Coder-480B-A35B-Instruct/blob/main/generation_config.json
        --   "pad_token_id": 151643,
        --   "do_sample": true,
        --   "eos_token_id": [
        --     151645,
        --     151643
        --   ],
        --   "repetition_penalty": 1.05,
        --   "temperature": 0.7,
        --   "top_p": 0.8,
        --   "top_k": 20
        --
        --     --   TODO! are these all the correct param names and location for llama-server?
        pad_token_id = 151643,
        do_sample = true,
        eos_token_id = { 151645, 151643 },
        repetition_penalty = 1.05, -- TODO this appears to be repeat_penalty?
        temperature = 0.7,
        top_p = 0.8,
        top_k = 20,
        --     --   TODO! put these into predictions AND ask questions ...
    }
    return default_to_recommended(request_body, recommended)
end

function M.new_qwen25coder_ollama_body(request_body)
    -- get values from rewrite/ask/predictions
    -- PRN I should run some tests too, I never optimized using 2.5-Coder!
    --   keep in mind it had both base and instruct variants
end

return M
