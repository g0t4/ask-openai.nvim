local log = require("ask-openai.logs.logger")
local api = require("ask-openai.api")
local dedupe = require("ask-openai.rag.client.dedupe")

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

Reasoning: ]] .. api.get_reasoning_level() [[

# Valid channels: analysis, commentary, final. Channel must be included for every message.
]]

    table.insert(self._parts, "<|start|>system<|message|>" .. message .. "<|end|>")
    return self
end

HarmonyRawFimPromptBuilder.developer_message = vim.trim([[
You are completing code from a Neovim plugin.
As the user types, the plugin suggests code completions based on their cursor position marked with: <|fim_middle|>
The surrounding code is limited to X lines above/below the cursor, so it may not be the full file. Focus on the code near <|fim_middle|>
Do NOT explain your decisions. Do NOT return markdown blocks ```
Do NOT repeat surrounding code (suffix/prefix)
ONLY return valid code at the <|fim_middle|> position
PAY attention to existing whitespace.
YOU ARE ONLY INSERTING CODE, DO NOT REPEAT PREFIX/SUFFIX. Think about overlap before finishing your thoughts.

For example, if you see this in a python file:
def adder(a, b):
    return <|fim_middle|> + b

The correct completion is:
a

NOT:
a + b

and NOT:
    return a + b

]])

--- developer message (harmony spec):
--- - instructions for the model (what is normally considered the “system prompt”)
--- - and available function tools
---@return HarmonyRawFimPromptBuilder self
function HarmonyRawFimPromptBuilder:developer()
    table.insert(self._parts, "<|start|>developer<|message|>" .. HarmonyRawFimPromptBuilder.developer_message .. "<|end|>")
    return self
end

---@param request OllamaFimBackend
function HarmonyRawFimPromptBuilder.context_user_msg(request)
    local context_lines = {
        "Here is context that's automatically provided, that MAY be relevant.",
        "repo: " .. request:get_repo_name(),
        "",
        vim.trim([[
General project code rules:
- Never add comments to the end of a line.
- NEVER add TODO comments for me.
]]),
    }

    local context = request.context
    if context.includes.yanks and context.yanks then
        table.insert(context_lines, context.yanks.content)
    end
    -- if context.includes.matching_ctags and context.matching_ctags then
    --     table.insert(context_lines, context.matching_ctags)
    -- end
    if context.includes.project and context.project then
        vim.iter(context.project)
            :each(function(value)
                table.insert(context_lines, value.content)
            end)
    end

    if request.rag_matches and #request.rag_matches > 0 then
        local rag_parts = {}
        if #request.rag_matches == 1 then
            heading = "# RAG query match:\n"
        elseif #request.rag_matches > 1 then
            heading = "# RAG query matches: " .. #request.rag_matches .. "\n"
        end
        table.insert(rag_parts, heading)

        -- TODO! dedupe matches that overlap/touch dedupe.merge_contiguous_rag_chunks()
        vim.iter(request.rag_matches)
            :each(function(chunk)
                ---@cast chunk LSPRankedMatch
                local file = chunk.file .. ":" .. chunk.start_line_base0 .. "-" .. chunk.end_line_base0
                local code_chunk = chunk.text
                table.insert(rag_parts,
                    "## " .. file .. "\n"
                    .. code_chunk .. "\n"
                )
            end)
        local rag_context = table.concat(rag_parts, "\n")
        table.insert(context_lines, rag_context)
    end

    return table.concat(context_lines, "\n")
end

---@param request OllamaFimBackend
function HarmonyRawFimPromptBuilder.fim_prompt(request)
    -- * user message
    local current_file_relative_path = request.inject_file_path_test_seam()
    local file_prefix = ""
    if current_file_relative_path == nil then
        log:warn("current_file_name is nil")
        current_file_relative_path = ""
        file_prefix = "I am editing this file: " .. current_file_relative_path .. "\n\n"
    end

    --  TODO try PSM format anyways! I think it might help with repeating the suffix?
    --    might want to find a fine tune too that actually has training for PSM/SPM
    --    would need to reword some instructions above (including examples)
    local fim_user_message = file_prefix
        .. "Please complete <|fim_middle|> in the following code (which has carefully preserved indentation):\n"
        .. request.ps_chunk.prefix
        .. "<|fim_middle|>"
        .. request.ps_chunk.suffix
    return fim_user_message
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
    -- PRN add after I test context (and it feels like the model isn't paying attention to it)
    --   "Do not forget, the neovim plugin automaticaly collected context to consider. It's included above, in a previous message. I won't blindly repeat it."
    --
    -- vim.trim - strip leading/trailing whitespace so I can format my [[ ]] literal as I see fit
    -- - also harmony has no \n between messages, \n should only come within a message text field
    local deep_thoughts_about_fim = vim.trim([[
The user is asking for a code completion.
They provided the existing code with a <|fim_middle|> tag where their cursor is currently located. Whatever I provide will replace <|fim_middle|>
To clarify, the code before <|fim_middle|> is the prefix. The code after is the suffix.
I am not changing the prefix nor the suffix.
I will NOT wrap my response in ``` markdown blocks.
I will not explain anything.
They also carefully preserved indentation, so I need to carefully consider indentation in my response.
I will fill-in-the-middles in the most awesome way!
]])
    -- FYI adding blurb about no ``` and markdown worked well to stop that!
    -- TODO! detect line break before/after <|fim_middle|> and adjust the thought about modifying an existing line of code accordingly?
    --   present this as a reflective thought from the model:
    --     If there's no line break before <|fim_middle|> and/or after, then that means I am completing code on a line of existing code. Do not repeat the rest of the line either!
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
