

-- TODO extract interface from /v1/completions builder and reuse that here...
--    can I define an interface in lua?
--    then use a backend variable in handlers.lua... w/ completion regardless of backend
--       local backend = require("../backends/x")


    -- FYI only needed for raw prompts:
    local tokens_to_clear = "<|endoftext|>"
    local fim = {
        enabled = true,
        prefix = "<|fim_prefix|>",
        middle = "<|fim_middle|>",
        suffix = "<|fim_suffix|>",
    }

    -- TODO provide guidance before fim_prefix... can I just <|im_start|> blah <|im_end|>? (see qwen2.5-coder template for how it might work)
    -- TODO setup separate request/response handlers to work with both /api/generate AND /v1/completions => use config to select which one
    --    TEST w/o deepseek-r1 using api/generate with FIM manual prompt ... which should work ... vs v1/completions for deepseek-r1:7b should fail to FIM or not well

    -- TODO try repo level code completion: https://github.com/QwenLM/Qwen2.5-coder?tab=readme-ov-file#4-repository-level-code-completion
    --    this is not FIM, rather it is like AR... give it <|repo_name|> and then multiple files delimited with <|file_sep|> and name and then contents... then last file is only partially complete (it generates the rest of it)
    -- The more I think about it, the less often I think I use the idea of FIM... I really am just completing (often w/o a care for what comes next)... should I be trying non-FIM too? (like repo level completions?)
    -- PSM inference format:
    -- local raw_prompt = fim.prefix .. context_before_text .. fim.suffix .. context_after_text .. fim.middle

