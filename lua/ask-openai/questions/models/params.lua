local log = require("ask-openai.logs.logger").predictions()

local M = {}

function default_to_recommended(request_body, recommended)
    -- rightmost wins
    local merged = vim.tbl_deep_extend("force", recommended, request_body or {})
    log:info("merged request body: " .. vim.inspect(merged))
    return merged
end

function M.new_gptoss_chat_body_llama_server(request_body)

end

function M.new_qwen3coder_llama_server_chat_body(request_body) -- this is a duplicate
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

end

return M
