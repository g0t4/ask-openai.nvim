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
    ["200000"] = "<|reserved_200000|>",
    ["200001"] = "<|reserved_200001|>",
    ["200002"] = "<|return|>",
    ["200003"] = "<|constrain|>",
    ["200004"] = "<|reserved_200004|>",
    ["200005"] = "<|channel|>",
    ["200006"] = "<|start|>",
    ["200007"] = "<|end|>",
    ["200008"] = "<|message|>",
    ["200009"] = "<|reserved_200009|>",
    ["200010"] = "<|reserved_200010|>",
    ["200011"] = "<|reserved_200011|>",
    ["200012"] = "<|call|>",
    ["200013"] = "<|reserved_200013|>",
    ["200014"] = "<|reserved_200014|>",
    ["200015"] = "<|reserved_200015|>",
    ["200016"] = "<|reserved_200016|>",
    ["200017"] = "<|reserved_200017|>",
    ["200018"] = "<|endofprompt|>",

    -- cat tokenizer_config.json | jq .'added_tokens_decoder | to_entries | .[] | "[\"\(.value.content)\"]=\(.key)," ' -r
    -- token => ID
    ["<|startoftext|>"] = 199998,
    ["<|endoftext|>"] = 199999,
    ["<|reserved_200000|>"] = 200000,
    ["<|reserved_200001|>"] = 200001,
    ["<|return|>"] = 200002,
    ["<|constrain|>"] = 200003,
    ["<|reserved_200004|>"] = 200004,
    ["<|channel|>"] = 200005,
    ["<|start|>"] = 200006,
    ["<|end|>"] = 200007,
    ["<|message|>"] = 200008,
    ["<|reserved_200009|>"] = 200009,
    ["<|reserved_200010|>"] = 200010,
    ["<|reserved_200011|>"] = 200011,
    ["<|call|>"] = 200012,
    ["<|reserved_200013|>"] = 200013,
    ["<|reserved_200014|>"] = 200014,
    ["<|reserved_200015|>"] = 200015,
    ["<|reserved_200016|>"] = 200016,
    ["<|reserved_200017|>"] = 200017,
    ["<|endofprompt|>"] = 200018,

}

return M
