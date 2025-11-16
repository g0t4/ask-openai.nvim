local M = {}

-- NOTES:
-- - o200k_harmony tokenizer
--   - extends o200k tokenizer w/ harmony format tokens (used by gpt4o and o4-mini)
--   - https://github.com/openai/tiktoken/blob/97e49cbadd500b5cc9dbb51a486f0b42e6701bee/tiktoken_ext/openai_public.py#L123-L151
--   - all special tokens use <|type|> format
--

M.special_tokens = {

    -- https://huggingface.co/openai/gpt-oss-20b/blob/main/tokenizer_config.json
    -- "tokenizer_class": "PreTrainedTokenizerFast"

    -- top level tokens mapped:
    bos_token = "<|startoftext|>",
    eos_token = "<|return|>",
    pad_token = "<|endoftext|>",

    -- cat tokenizer_config.json | jq .'added_tokens_decoder | to_entries | .[] | "[\"\(.key)\"]=\"\(.value.content)\"," ' -r
    -- ID => token
    ["199998"] = "<|startoftext|>",
    ["199999"] = "<|endoftext|>",
    ["200002"] = "<|return|>",
    ["200003"] = "<|constrain|>",
    ["200005"] = "<|channel|>",
    ["200006"] = "<|start|>",
    ["200007"] = "<|end|>",
    ["200008"] = "<|message|>",
    ["200012"] = "<|call|>",
    ["200018"] = "<|endofprompt|>",

    -- cat tokenizer_config.json | jq .'added_tokens_decoder | to_entries | .[] | "[\"\(.value.content)\"]=\(.key)," ' -r
    -- token => ID
    ["<|startoftext|>"] = 199998,
    ["<|endoftext|>"] = 199999,
    ["<|return|>"] = 200002,
    ["<|constrain|>"] = 200003,
    ["<|channel|>"] = 200005,
    ["<|start|>"] = 200006,
    ["<|end|>"] = 200007,
    ["<|message|>"] = 200008,
    ["<|call|>"] = 200012,
    ["<|endofprompt|>"] = 200018,

    -- convenient constants:
    STARTOFTEXT = 199998,
    ENDOFTEXT = 199999,
    RETURN = 200002,
    CONSTRAIN = 200003,
    CHANNEL = 200005,
    START = 200006,
    END = 200007,
    MESSAGE = 200008,
    CALL = 200012,
    ENDOFPROMPT = 200018,
}
return M
