local log = require("ask-openai.logs.logger").predictions()
local api = require("ask-openai.api")
local dedupe = require("ask-openai.rag.client.dedupe")
local harmony = require("ask-openai.backends.models.gptoss.tokenizer").harmony
local TxChatMessage = require("ask-openai.questions.chat.messages.tx")
local qwen = require("ask-openai.backends.models.fim").qwen25coder.sentinel_tokens
local prompts = require("ask-openai.frontends.prompts")

---@class HarmonyFimPromptBuilder
---@field _parts string[]
local HarmonyFimPromptBuilder = {}
HarmonyFimPromptBuilder.__index = HarmonyFimPromptBuilder

---@return HarmonyFimPromptBuilder self
function HarmonyFimPromptBuilder.new()
    local self = setmetatable({
        _parts = {}
    }, HarmonyFimPromptBuilder)
    return self
end

--- system message (harmony spec):
--- - specify reasoning effort
--- - meta information like
---   - knowledge cutoff
---   - built-in tools
---@return HarmonyFimPromptBuilder self
function HarmonyFimPromptBuilder:system()
    -- reasoning level: high/medium/low - https://arxiv.org/html/2508.10925v1#S2.SS5.SSS2
    -- I could add a streamdeck button/toggle to switch level
    -- - And instead of forcing instant response, I could start the thoughts section and let it finish it.
    --   i.e. prompt it to finish thoughts about the specific code in the example
    --   "Ok now I should review the code itself and take some notes..."
    -- - Just keep in mind, if you want thinking, you can always use AskRewrite or AskQuestion too (make sure those aren't a fit before modifying FIM for this)
    --   with thinking I can't imagine you're not talking about an Edit Prediction (less FIM)

    local message = [[
You are ChatGPT, a large language model trained by OpenAI.
Knowledge cutoff: 2024-06
Current date: 2025-11-07

Reasoning: ]] .. api.get_fim_reasoning_level() [[

# Valid channels: analysis, commentary, final. Channel must be included for every message.
]]

    table.insert(self._parts, harmony.START .. "system" .. harmony.MESSAGE .. message .. harmony.END)
    return self
end

HarmonyFimPromptBuilder.developer_message = vim.trim([[
You are completing code from a Neovim plugin.
As the user types, the plugin suggests code completions based on their cursor position marked with: ]] .. qwen.FIM_MIDDLE .. [[

The surrounding code is limited to X lines above/below the cursor, so it may not be the full file. Focus on the code near ]] .. qwen.FIM_MIDDLE .. [[
Do NOT explain your decisions. Do NOT return markdown blocks ```
Do NOT repeat surrounding code (suffix/prefix)
ONLY return valid code at the ]] .. qwen.FIM_MIDDLE .. [[ position
PAY attention to existing whitespace.
YOU ARE ONLY INSERTING CODE, DO NOT REPEAT PREFIX/SUFFIX.

For example, when the current line has both prefix and suffix:
```python
def area(width, height):
    return ]] .. qwen.FIM_MIDDLE .. [[ * height

# The correct completion is:
width

# NOT repeating the suffix:
width * height

# and NOT repeating both suffix and prefix:
    return width * height
```

]])
-- TODO add example of indentation

--- developer message (harmony spec):
--- - instructions for the model (what is normally considered the “system prompt”)
--- - and available function tools
---@return HarmonyFimPromptBuilder self
function HarmonyFimPromptBuilder:developer()
    table.insert(self._parts, harmony.START .. "developer" .. harmony.MESSAGE .. HarmonyFimPromptBuilder.developer_message .. harmony.END)
    return self
end

---@param request FimBackend
function HarmonyFimPromptBuilder.context_user_msg(request)
    local context_lines = {
        "Here is context that's automatically provided, that MAY be relevant.",
        "repo: " .. request:get_repo_name(),
        "",
        vim.trim([[
## General project code rules:
- Never add comments to the end of a line.
- NEVER add TODO comments for me.
]]),
    }
    local function add_blank_line()
        table.insert(context_lines, "")
    end

    local context = request.context
    if context.includes.project and context.project then
        vim.iter(context.project)
            :each(function(value)
                add_blank_line()
                table.insert(context_lines, value.content)
            end)
    end

    if context.includes.yanks and context.yanks then
        add_blank_line()
        table.insert(context_lines, context.yanks.content)
    end

    -- if context.includes.matching_ctags and context.matching_ctags then
    --     add_blank_line()
    --     table.insert(context_lines, context.matching_ctags.content)
    -- end

    return table.concat(context_lines, "\n")
end

---@param request FimBackend
function HarmonyFimPromptBuilder.fim_prompt(request)
    -- * user message
    local current_file_relative_path = request.inject_file_path_test_seam()
    local file_prefix = ""
    if current_file_relative_path == nil then
        log:warn("current_file_name is nil")
    else
        file_prefix = "I am editing this file: " .. current_file_relative_path .. "\n\n"
    end

    local fim_user_message = file_prefix
        .. "Please complete " .. qwen.FIM_MIDDLE .. " in the following code (which has carefully preserved indentation):\n"
        .. request.ps_chunk.prefix
        .. qwen.FIM_MIDDLE
        .. request.ps_chunk.suffix
    return fim_user_message
end

--- user message (harmony spec):
--- - Typically representing the input to the model
---@param message? string|{content:string}|TxChatMessage -- nil/empty so consumers can always call (and it won't be added), TxChatMessage will extract message.content
---@return HarmonyFimPromptBuilder self
function HarmonyFimPromptBuilder:user(message)
    if message.content then
        -- for TxChatMessage
        message = message.content
    end
    if message == nil or message == "" then
        -- don't add an empty message
        return self
    end

    table.insert(self._parts, harmony.START .. "user" .. harmony.MESSAGE .. message .. harmony.END)
    return self
end

-- * deep_thoughts_about_fim
-- TODO try qwen25coder format? and thinking to explain it?
--   The user is asking for a FIM completion. Likely for code they are writing.
--   And it looks like they are providing a qwen2.5-coder compatible FIM prompt.
--   I should response like Qwen2.5-Coder would respond.
--   I will fill-in-the-middles in the most awesome way!

-- FYI these are NOT instructions, INSTEAD they are the model's observations!
-- - So you can use them as instructions just word them appropriately
-- - What do you want the model to have observed?
-- ?? should I get gptoss to do this without myself and copy its style instead of wording them myself?
--
-- PRN add after I test context (and it feels like the model isn't paying attention to it)
--   "Do not forget, the neovim plugin automaticaly collected context to consider. It's included above, in a previous message. I won't blindly repeat it."
--
-- vim.trim - strip leading/trailing whitespace so I can format my [[ ]] literal as I see fit
-- - also harmony has no \n between messages, \n should only come within a message text field
HarmonyFimPromptBuilder.deep_thoughts_about_fim = vim.trim([[
The user is asking for a code completion.
They provided the existing code with a ]] .. qwen.FIM_MIDDLE .. [[ tag where their cursor is currently located. Whatever I provide will replace ]] .. qwen.FIM_MIDDLE .. [[
To clarify, the code before ]] .. qwen.FIM_MIDDLE .. [[ is the prefix. The code after is the suffix.
I am not changing the prefix nor the suffix.
I will NOT wrap my response in ``` markdown blocks.
I will not explain anything.
They also carefully preserved indentation, so I need to carefully consider indentation in my response.
I will fill-in-the-middles in the most awesome way!
]])
-- FYI adding blurb about no ``` and markdown worked well to stop that!
-- TODO! detect line break before/after (qwen.FIM_MIDDLE) and adjust the thought about modifying an existing line of code accordingly?
--   present this as a reflective thought from the model:
--     If there's no line break before (qwen.FIM_MIDDLE) and/or after, then that means I am completing code on a line of existing code. Do not repeat the rest of the line either!
-- YES! repeat the CURRENT LINE HERE as an observation!!! And maybe even state what I shouldn't duplicate! (this might help with repeating on same line (almost always right now when there's code on same line after cursor)
--   MAYBE mention its indentation too instead of other indentation comments above (I can say this line has X indent so I need to respect that)
--   IF there's code before and after the cursor on the current line, reflect that this is likely just a fill in the middle of this line only, not a multi line response (not likely anyways)

---@return HarmonyFimPromptBuilder self
function HarmonyFimPromptBuilder:set_thinking()
    table.insert(self._parts,
        harmony.msg_assistant_analysis(HarmonyFimPromptBuilder.deep_thoughts_about_fim))
    return self
end

---@return HarmonyFimPromptBuilder self
function HarmonyFimPromptBuilder:start_assistant_final_response()
    -- make it so the model only ends with the prediction and maybe harmony.END
    -- FYI in testing harmony.END is not showing up, which is fine by me! 99% sure llama-server detects that as stop token and it normally won't return those unless configured to do so
    table.insert(self._parts, harmony.force_final())
    return self
end

---@return string prompt
function HarmonyFimPromptBuilder:build_raw_prompt()
    -- join w/ no character (do not use \n)
    return table.concat(self._parts, "")
end

HarmonyFimPromptBuilder.gptoss = {
    sentinel_tokens = {}
}

---@param request FimBackend
function HarmonyFimPromptBuilder.gptoss.RETIRED_get_fim_raw_prompt_no_thinking(request)
    -- FYI this builder might be useful if I want to work with raw prompts for another use case...
    --  but I found prefill in llama-cpp (llama-server) so I don't need raw anymore for FIM w/o thinking purposes

    -- TODO experiment 2 - combination of fixed thinking start + partial thinking finish
    --   add my thinking reflections from above...
    --   then let the model finish thinking?
    --   use new harmony parser for raw /completions output parsing

    -- TODO if I allow the model to finish the reasoning... that might be best!
    --   Ask it to practice its change before it decides
    -- I could update my example too:
    -- {CHANNEL}analysis{MESSAGE}
    -- Let's practice the change first.
    -- I need to insert a variable name between 'return' and '+ b'.
    -- Candidate: a
    -- Check: would that make 'return a + b'? Yes.
    -- So the correct insertion is 'a'.
    -- {CHANNEL}final{MESSAGE}

    local builder = HarmonyFimPromptBuilder.new()
        :developer()
        :user(HarmonyFimPromptBuilder.context_user_msg(request))
        :user(prompts.semantic_grep_user_message(request.rag_matches))
        :user(HarmonyFimPromptBuilder.fim_prompt(request))
        :set_thinking()
        :start_assistant_final_response() -- this forces the model to respond w/o any further thinking

    return builder:build_raw_prompt()
end

---@param request FimBackend
---@param level GptOssReasoningLevel
function HarmonyFimPromptBuilder.gptoss.get_fim_chat_messages(request, level)
    -- TODO what if I change this to ask gptoss to rewrite the current line (only current line)
    --  and then FIM just replaces that line?
    --  OR, add a shortcut key to accept FIM as replace current line?
    --  not always, but sometimes gptoss still suggests entire line (espeically for partial lines)
    --    why not work around that or encourage that?
    --    I can even diff the current line vs the generated to see what to insert so I don't have to do extmarks that replace the full line

    local dev = HarmonyFimPromptBuilder.developer_message
    -- FYI! first line of [[ not included if it is empty, so no trailing \n on first line! Thus I had to add some blank lines I wanted in my prompt
    -- FYI if/when you test out using partial thinking with raw template above, then put this into the shared developer message
    dev = dev .. [[


Make sure to practice the code change before you return a suggestion. Take the cursor line (at least) and type it out with the new code and make sure it is valid, correct code.
]]

    local messages = {
        TxChatMessage:developer(dev), -- FYI developer or system message must be first, and ONLY ONE is allowed
        TxChatMessage:user(HarmonyFimPromptBuilder.context_user_msg(request)),
    }
    local rag_message = prompts.semantic_grep_user_message(request.rag_matches)
    if rag_message then
        table.insert(messages, rag_message)
    end
    table.insert(messages, TxChatMessage:user(HarmonyFimPromptBuilder.fim_prompt(request)))
    if level == "off" then
        -- TODO get rid of raw prompt approach above? or just keep it around as "RETIRED" ??
        local fixed_thoughts = HarmonyFimPromptBuilder.deep_thoughts_about_fim

        -- FYI "{START}assistant" is at end of prompt (see add_generation_prompt in jinja template + in chat logic)
        --   https://github.com/ggml-org/llama.cpp/blob/7d77f0732/models/templates/openai-gpt-oss-120b.jinja#L328-L330
        --   thus my `prefill` (below) starts with a channel
        --   BTW my `prefill` is appended to the raw prompt (after jinja is rendered):
        --     https://github.com/ggml-org/llama.cpp/blob/7d77f0732/tools/server/utils.hpp#L754-L762
        local prefill = harmony.CHANNEL .. "analysis" .. harmony.MESSAGE .. fixed_thoughts .. harmony.END
            .. harmony.START .. "assistant" -- WORKS!

        -- *** notes w.r.t. final prefill text (last message)
        -- FYI using special token universal convention: {} and uppercase
        -- .. "{START}assistant" -- * WORKS!
        --   luckily, finishing prefill with `{START}assistant` is enough for gptoss to produce the final message!
        --   IIAC you can't have back to back analysis channel messages, or at least not normally?
        --     and commentary channel doesn't make sense because no tools passed
        --     so the model is only left with the final channel! (phew)
        --   (btw... this is the same as it would add w/o my prefill)

        -- * FAILED:
        -- .. "{START}assistant{CHANNEL}final{MESSAGE}" -- FAIL
        -- along the way shows:
        --   llama-server: Partial parse: incomplete header
        -- at end it does recognize generated text as the content (net effect is as if it were not a streaming response b/c it all arrives on last delta!)
        --   llama-server: Partial parse: incomplete header
        --   llama-server: Parsed message: {"role":"assistant","content":"function M.mul(a, b)\n    return a * b\nend\n\nfunction M.div(a, b)\n    if b == 0 then\n        error(\"division by zero\")\n    end\n    return a / b\nend"}
        --
        -- .. "{START}assistant{CHANNEL}final"  -- FAIL
        --
        -- .. "{START}assistant{CHANNEL}" -- FAIL results in these key messages:
        --   llama-server: common_chat_parse_gpt_oss: unknown header from message: final
        --   llama-server: common_chat_parse_gpt_oss: content after last message: final{MESSAGE}function M.mul(a, b)
        --



        -- llama-cpp uses this last assistant message for prefill purposes (will not terminate with {END})
        table.insert(messages, TxChatMessage:assistant(prefill))

        -- TODO add nvim command to verify prompts:
        --   TODO AskDumpApplyTemplates (dump all in one go is probably best to compare)
    end

    return messages
end

return HarmonyFimPromptBuilder
