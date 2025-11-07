---@class HarmonyRawFimPromptBuilder
---@field _parts string[]
local HarmonyRawFimPromptBuilder = {}
HarmonyRawFimPromptBuilder.__index = HarmonyRawFimPromptBuilder

-- TODO use the OOB system message? any difference in performance?
-- "<|start|>system<|message|>You are ChatGPT, a large language model trained by OpenAI.\nKnowledge cutoff: 2024-06\nCurrent date: 2025-11-07\n\nReasoning: medium\n\n# Valid channels: analysis, commentary, final. Channel must be included for every message.<|end|><|start|>user<|message|><|file_sep|>calculator.lua\n<|fim_prefix|>function a<|fim_suffix|><|fim_middle|><|end|><|start|>assistant<|channel|>analysis<|message|>The user is asking for a FIM completion. Likely for code they are writing. And it looks like they are providing a qwen2.5-coder compatible FIM prompt. I should response like Qwen2.5-Coder would respond. I will fill-in-the-middles in the most awesome way!<|end|><|start|>assistant<|channel|>final"

---@return HarmonyRawFimPromptBuilder self
function HarmonyRawFimPromptBuilder.new()
    local self = setmetatable({
        _parts = {} -- internal list of raw strings
    }, HarmonyRawFimPromptBuilder)
    return self
end

---@param message string
---@return HarmonyRawFimPromptBuilder self
function HarmonyRawFimPromptBuilder:system(message)
    -- TODO drop <|end|> to encourage the response to exclude it :) ??
    table.insert(self._parts, "<|start|>system<|message|>" .. message .. "<|end|>")
    return self
end

---@param message string
---@return HarmonyRawFimPromptBuilder self
function HarmonyRawFimPromptBuilder:user(message)
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

    -- strip leading/trailing whitespace so I can format my [[ ]] literal as I see fit
    -- also harmony has no \n between messages, \n should only come within a message text field
    local thoughts = vim.trim([[
The user is asking for a FIM completion. They provided code with a prefix and suffix and then I need to fill in the code where it says <<<FIM>>>. So I need to imagine what would fit really well in <<<FIM>>>. I will fill-in-the-middles in the most awesome way!
]])

    table.insert(self._parts, "<|start|>assistant<|channel|>analysis<|message|>" .. thoughts .. "<|end|>")
    return self
end

---@return HarmonyRawFimPromptBuilder self
function HarmonyRawFimPromptBuilder:start_assistant_final_response()
    -- make it so the model only ends with the prediction and maybe <|end|>
    table.insert(self._parts, "<|start|>assistant<|channel|>final<|message|>")
    return self
end

---@return string prompt
function HarmonyRawFimPromptBuilder:build_raw_prompt()
    -- join w/ no character (do not use \n)
    return table.concat(self._parts, "")
end

return HarmonyRawFimPromptBuilder
