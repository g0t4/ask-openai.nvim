---@class HarmonyRawFimPromptBuilder
---@field _parts string[]
local HarmonyRawFimPromptBuilder = {}
HarmonyRawFimPromptBuilder.__index = HarmonyRawFimPromptBuilder

---@return HarmonyRawFimPromptBuilder self
function HarmonyRawFimPromptBuilder.new()
    local self = setmetatable({
        _parts = {}
    }, HarmonyRawFimPromptBuilder)
    return self
end

--- system message (harmony spec):
--- - specify reasoning effort
--- - meta information like
---   - knowledge cutoff
---   - built-in tools
---@return HarmonyRawFimPromptBuilder self
function HarmonyRawFimPromptBuilder:system()
    -- ? add reasoning level arg: high/medium/low
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

Reasoning: low

# Valid channels: analysis, commentary, final. Channel must be included for every message.
]]

    table.insert(self._parts, "<|start|>system<|message|>" .. message .. "<|end|>")
    return self
end

--- developer message (harmony spec):
--- - instructions for the model (what is normally considered the “system prompt”)
--- - and available function tools
---@param message string
---@return HarmonyRawFimPromptBuilder self
function HarmonyRawFimPromptBuilder:developer(message)
    table.insert(self._parts, "<|start|>developer<|message|>" .. message .. "<|end|>")
    return self
end

--- user message (harmony spec):
--- - Typically representing the input to the model
---@param message string
---@return HarmonyRawFimPromptBuilder self
function HarmonyRawFimPromptBuilder:user(message)
    if not message then
        -- don't add an empty message
        return self
    end
    table.insert(self._parts, "<|start|>user<|message|>" .. message .. "<|end|>")
    return self
end

---@return HarmonyRawFimPromptBuilder self
function HarmonyRawFimPromptBuilder:set_thinking()
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
    -- vim.stip - strip leading/trailing whitespace so I can format my [[ ]] literal as I see fit
    -- - also harmony has no \n between messages, \n should only come within a message text field
    local deep_thoughts_about_fim = vim.trim([[
The user is asking for a code completion.
They provided the existing code with a <<<CURSOR>>> tag where their cursor is currently located. Whatever I provide will replace <<<CURSOR>>>
To clarify, the code before <<<CURSOR>>> is the prefix. The code after is the suffix.
I am not changing the prefix nor the suffix.
Do not forget, the neovim plugin automaticaly collected context to consider. It's included above, in a previous message. I won't blindly repeat it.
I will NOT wrap my response in ``` markdown blocks.
I will not explain anything.
They also carefully preserved indentation, so I need to carefully consider indentation in my response.
I will fill-in-the-middles in the most awesome way!
]])
    -- FYI adding blurb about no ``` and markdown worked well to stop that!
    -- TODO! detect line break before/after <<<CURSOR>>> and adjust the thought about modifying an existing line of code accordingly?
    --   present this as a reflective thought from the model:
    --     If there's no line break before <<<CURSOR>>> and/or after, then that means I am completing code on a line of existing code. Do not repeat the rest of the line either!
    -- YES! repeat the CURRENT LINE HERE as an observation!!! And maybe even state what I shouldn't duplicate! (this might help with repeating on same line (almost always right now when there's code on same line after cursor)
    --   MAYBE mention its indentation too instead of other indentation comments above (I can say this line has X indent so I need to respect that)
    --   IF there's code before and after the cursor on the current line, reflect that this is likely just a fill in the middle of this line only, not a multi line response (not likely anyways)

    table.insert(self._parts, "<|start|>assistant<|channel|>analysis<|message|>" .. deep_thoughts_about_fim .. "<|end|>")
    return self
end

---@return HarmonyRawFimPromptBuilder self
function HarmonyRawFimPromptBuilder:start_assistant_final_response()
    -- make it so the model only ends with the prediction and maybe <|end|>
    -- FYI in testing <|end|> is not showing up, which is fine by me!
    table.insert(self._parts, "<|start|>assistant<|channel|>final<|message|>")
    return self
end

---@return string prompt
function HarmonyRawFimPromptBuilder:build_raw_prompt()
    -- join w/ no character (do not use \n)
    return table.concat(self._parts, "")
end

return HarmonyRawFimPromptBuilder
