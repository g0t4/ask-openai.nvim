local M = {}



-- NOTES:
-- - o200k_harmony tokenizer
--   - extends o200k tokenizer w/ harmony format tokens (used by gpt4o and o4-mini)
--   - https://github.com/openai/tiktoken/blob/97e49cbadd500b5cc9dbb51a486f0b42e6701bee/tiktoken_ext/openai_public.py#L123-L151
--   - all special tokens use <|type|> format
--

-- FORMAT
--   messages: <|start|>{header}<|message|>{content}<|end|>
--   stop tokens: <|return|> (at end of final channel's message), <|call|> (often at end of commentary channel's message)
--
--   analysis channel = CoT    (typically first)
--     - not trained for safety, avoid showing it to users
--     - drop this in history, once a final channel message is generated
--       - except in tool calling (which can be part of CoT)
--   commentary channel = tool call request (one or more)
--     - recipient (in either role or channel)
--   final channel = traditional response (last)
--     - trained for safety
--     <|return|> is only a stop token (for decode)...
--     - replace <|return|> with <|end|> when sending chat history
--     - unless training (i.e. fine tune) then you can leave <|return|>
--
-- message types:
-- * system message (not traditional system prompt)
--   - https://cookbook.openai.com/articles/openai-harmony#system-message-format
--      TODO UPDATE your FIM BUILDER (non-thinking at least used this)
--   - mostly use the fixed text examples (don't change)
--   - about all you want to customize: dates/reasoning_effort
--      Reasoning: high/medium/low
--   - builtin tools (python, browser)
--     - browser tools - dedicated namespace : search, open, find
--       - parallel to functions namespace in developer message
--     - python tool is singular => no definitions, model simply puts python code into the <|message|>
--   -  required channels:
--       add: "# Valid channels: analysis, commentary, final. Channel must be included for every message."
--   - if using tools:
--       add: "Calls to these tools must go to the commentary channel: 'functions'."
--
-- * developer message
--   - traditional system prompt (instructions)
--   - section: # Tools
--     - tool definitions (not builtin tools)
--     - https://cookbook.openai.com/articles/openai-harmony#function-calling
--   - section: # Response Formats
--     - structured output
--     - https://cookbook.openai.com/articles/openai-harmony#structured-output
--
--
--   no tools, use:
--     <|start|>developer<|message|># Instructions
--     {instructions}<|end|>
--
-- * Preamble in commentary channel
--   instead of commentary channel w/ tool call
--   preamble is commentary channel with message intended for user
--     not same as CoT... should be shown to the user
--     FYI no recipient is the difference! (thus not a tool call)
--
-- * Tool (result) message
-- <|start|>{toolname} to=assistant<|channel|>commentary<|message|>{output}<|end|>
--    note the recipient to=assistant
--
-- * Tool calls
--   - AFAICT only supports single tool calls
--     - channel commentary has no mechanism to represent multiple tool calls, it's only one at a time
--     - model stops on <|call|>
--     - can have back to back tool calls
--     - all in the same CoT - that is the beauty of this model
--        - one request in => CoT (analysis) => tool call => CoT (etc) => one "final" response
--
--   - largely for tool calls in CoT



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
