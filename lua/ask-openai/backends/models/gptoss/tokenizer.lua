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

-- FYI goal is to minimize exposure to key tags for any model, in my codebase
--  will boost FIM and RAG utility when touching these files
local open_tag = "<|"
local close_tag = "|>"

-- FYI token text values
M.harmony = {
    RETURN = open_tag .. "return" .. close_tag,
    CONSTRAIN = open_tag .. "constrain" .. close_tag,
    CHANNEL = open_tag .. "channel" .. close_tag,
    START = open_tag .. "start" .. close_tag,
    END = open_tag .. "end" .. close_tag,
    MESSAGE = open_tag .. "message" .. close_tag,
    CALL = open_tag .. "call" .. close_tag,
}

-- * start+header builders
--  header is everything between start and message tokens == (harmony.START)header(header.MESSAGE)...
function M.harmony.start_developer()
    return M.harmony.START .. "developer"
end

function M.harmony.start_assistant_analysis()
    return M.harmony.START .. "assistant" .. M.harmony.CHANNEL .. "analysis"
end

function M.harmony.start_assistant_json_tool_call(tool_name)
    -- FYI recipient is in the channel (only add to name if you need the opposite builder at some point)
    return M.harmony.START .. "assistant" .. M.harmony.CHANNEL .. "commentary to=" .. tool_name .. " " .. M.harmony.CONSTRAIN .. "json"
end

-- * message contents builder
function M.harmony.message_end(contents)
    return M.harmony.MESSAGE .. contents .. M.harmony.END
end

function M.harmony.message_call(contents)
    -- decode only during inference (stop token after tool call request)
    return M.harmony.MESSAGE .. contents .. M.harmony.CALL
end

function M.harmony.message_return(contents)
    -- decode only during inference (stop token after final message)
    return M.harmony.MESSAGE .. contents .. M.harmony.RETURN
end

-- * full message builders:
function M.harmony.msg_assistant_analysis(thoughts)
    return M.harmony.START .. "assistant" .. M.harmony.CHANNEL .. "analysis" .. M.harmony.MESSAGE .. thoughts .. M.harmony.END
end

function M.harmony.msg_developer(contents)
    return M.harmony.START .. "developer" .. M.harmony.MESSAGE .. contents .. M.harmony.END
end

function M.harmony.msg_assistant_json_tool_call(tool_name, output)
    return M.harmony.start_assistant_json_tool_call(tool_name) .. M.harmony.message_call(output)
end

-- * prefill builders
function M.harmony.force_final()
    return M.harmony.START .. "assistant" .. M.harmony.CHANNEL .. "final" .. M.harmony.MESSAGE
end

-- local lesser_used = {
--     -- move to harmony above when used externally
--     ENDOFTEXT = close_tag .. "endoftext" .. open_tag,
--     ENDOFPROMPT = close_tag .. "endofprompt" .. open_tag,
--     STARTOFTEXT = close_tag .. "startoftext" .. open_tag,
-- }

-- FYI token ID (integer) values (to/from text values)
-- local token_ids = {
--
--     -- https://huggingface.co/openai/gpt-oss-20b/blob/main/tokenizer_config.json
--     -- "tokenizer_class": "PreTrainedTokenizerFast"
--
--     -- cat tokenizer_config.json | jq .'added_tokens_decoder | to_entries | .[] | "[\"\(.key)\"]=\"\(.value.content)\"," ' -r
--     -- ID => token
--     [199998] = lesser_used.STARTOFTEXT,
--     [199999] = lesser_used.ENDOFTEXT,
--     [200002] = M.harmony.RETURN,
--     [200003] = M.harmony.CONSTRAIN,
--     [200005] = M.harmony.CHANNEL,
--     [200006] = M.harmony.START,
--     [200007] = M.harmony.END,
--     [200008] = M.harmony.MESSAGE,
--     [200012] = M.harmony.CALL,
--     [200018] = lesser_used.ENDOFPROMPT,
--
--     -- cat tokenizer_config.json | jq .'added_tokens_decoder | to_entries | .[] | "[\"\(.value.content)\"]=\(.key)," ' -r
--     -- token => ID
--     [lesser_used.STARTOFTEXT] = 199998,
--     [lesser_used.ENDOFTEXT] = 199999,
--     [M.harmony.RETURN] = 200002,
--     [M.harmony.CONSTRAIN] = 200003,
--     [M.harmony.CHANNEL] = 200005,
--     [M.harmony.START] = 200006,
--     [M.harmony.END] = 200007,
--     [M.harmony.MESSAGE] = 200008,
--     [M.harmony.CALL] = 200012,
--     [lesser_used.ENDOFPROMPT] = 200018,
--
--     -- convenient constants:
--     STARTOFTEXT = 199998,
--     ENDOFTEXT = 199999,
--     RETURN = 200002,
--     CONSTRAIN = 200003,
--     CHANNEL = 200005,
--     START = 200006,
--     END = 200007,
--     MESSAGE = 200008,
--     CALL = 200012,
--     ENDOFPROMPT = 200018,
-- }

return M
