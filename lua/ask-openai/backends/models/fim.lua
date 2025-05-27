local M = {}

-- these models work for other purposes too...
--   but lets collect them under fim for now
--   really these are the fim related special tokens

M.qwen25coder = {
    sentinel_tokens = {
        fim_prefix = "<|fim_prefix|>",
        fim_middle = "<|fim_middle|>",
        fim_suffix = "<|fim_suffix|>",
        -- fim_pad = "<|fim_pad|>",
        repo_name = "<|repo_name|>",
        file_sep = "<|file_sep|>",
        im_start = "<|im_start|>",
        im_end = "<|im_end|>",
        -- endoftext = "<|endoftext|>"
    },
}

return M
