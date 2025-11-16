local M = {}

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

}

return M
