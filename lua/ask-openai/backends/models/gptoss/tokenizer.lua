local local_share = require("ask-openai.config.local_share")
local M = {}

---@param level any
---@return number
function M.get_gptoss_max_tokens_for_level(level)
    -- FYI if you want separate levels for say FIM vs AskQuestion/AskRewrite...
    --   consider passing the type here so it is all in one spot still.. the levels are?
    --   or just duplicate this function below and keep it all together

    if level == local_share.FimReasoningLevel.high then
        return 16384
    elseif level == local_share.FimReasoningLevel.medium then
        return 8192
    elseif level == local_share.FimReasoningLevel.low then
        return 4096
    elseif level == local_share.FimReasoningLevel.off then
        return 2048
    else
        return 2048
    end
end

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
