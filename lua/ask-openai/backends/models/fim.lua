local log = require("ask-openai.logs.logger").predictions()
local files = require("ask-openai.helpers.files")
local ansi = require("ask-openai.prediction.ansi")
local ChatThread = require("ask-openai.questions.chat_thread")
local ChatMessage = require("ask-openai.questions.chat_message")
local HarmonyRawFimPromptBuilder = require("ask-openai.backends.models.fim_harmony")

local M = {}

-- these models work for other purposes too...
--   but lets collect them under fim for now
--   really these are the fim related special tokens

M.gpt_oss = {
    sentinel_tokens = {
        -- fim_stop_tokens = [] -- TODO?
    }
}
---@param request OllamaFimBackend
function M.gpt_oss.get_fim_raw_prompt_no_thinking(request)
    -- TODO if I allow the model to finish the reasoning... that might be best!
    --   Ask it to practice its change before it decides
    -- I could update my example too:
    -- <analysis>
    -- Let's practice the change first.
    -- I need to insert a variable name between 'return' and '+ b'.
    -- Candidate: a
    -- Check: would that make 'return a + b'? Yes.
    -- So the correct insertion is 'a'.
    -- </analysis>
    -- <final>

    local developer_message = vim.trim([[
You are completing code from a Neovim plugin.
As the user types, the plugin suggests code completions based on their cursor (<<<CURSOR>>>) position.
The surrounding code is limited to X lines above/below the cursor, so it may not be the full file. Focus on the code near <<<CURSOR>>>
Do NOT explain your decisions. Do NOT return markdown blocks ```
Do NOT repeat surrounding code, especially pay attention to the suffix!
ONLY return valid code at the <<<CURSOR>> position

For example, if you see this in a python file:
def adder(a, b):
    return <<<CURSOR>>> + b

The correct completion is:
a

NOT:
a + b

and NOT:
    return a + b

]])
    -- * CONTEXT
    local context_lines = {
        "Here is context that's automatically provided, that MAY be relevant.",
        "repo: " .. request:get_repo_name()
    }
    local context = request.context
    if context.includes.yanks and context.yanks then
        table.insert(context_lines, context.yanks.content)
    end
    if request.context.includes.matching_ctags and request.context.matching_ctags then
        table.insert(context_lines, request.context.matching_ctags)
    end
    if context.includes.project and context.project then
        vim.iter(context.project)
            :each(function(value)
                table.insert(context_lines, value.content)
            end)
    end

    --     local instructions = ContextItem:new("instructions", [[
    -- General project code rules:
    -- - Never add comments to the end of a line.
    -- - NEVER add TODO comments for me.
    -- ]])
    --     append_file_non_fim(instructions)
    --
    --     if request.context.includes.yanks and request.context.yanks then
    --         append_file_non_fim(request.context.yanks)
    --     end
    --
    --     if request.context.includes.matching_ctags and request.context.matching_ctags then
    --         append_file_non_fim(request.context.matching_ctags)
    --     end
    --
    --     if request.context.includes.project and request.context.project then
    --         vim.iter(request.context.project)
    --             :each(append_file_non_fim)
    --     end
    --
    --     if request.rag_matches then
    --         vim.iter(request.rag_matches)
    --             :each(function(chunk)
    --                 ---@cast chunk LSPRankedMatch
    --                 local file_name = chunk.file .. ":" .. chunk.start_line_base0 .. "-" .. chunk.end_line_base0
    --                 local non_fim_file = tokens.file_sep .. file_name .. "\n" .. chunk.text
    --                 prompt = prompt .. non_fim_file
    --             end)
    --     end
    local rag_matches = request.rag_matches
    if enable_rag and rag_matches ~= nil and #rag_matches > 0 then
        rag_message_parts = {}
        if #rag_matches == 1 then
            heading = "# RAG query match: \n"
        elseif #rag_matches > 1 then
            heading = "# RAG query matches: " .. #rag_matches .. "\n"
        end
        table.insert(rag_message_parts, heading)
        vim.iter(rag_matches)
            :each(function(chunk)
                -- FYI this comes from embeddings query results... so the structure is different than other context providers
                -- include the line number range so if there are multiple matches it might be a bit more obvious that these are subsets of lines
                ---@cast chunk LSPRankedMatch
                local file = chunk.file .. ":" .. chunk.start_line_base0 .. "-" .. chunk.end_line_base0
                local code_chunk = chunk.text
                table.insert(rag_message_parts,
                    "## " .. file .. "\n"
                    .. code_chunk .. "\n"
                )
            end)
        table.insert(messages, ChatMessage:user(table.concat(rag_message_parts, "\n")))
    end

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
        .. "Please complete <<<CURSOR>>> in the following code (which has carefully preserved indentation):\n"
        .. request.ps_chunk.prefix
        .. "<<<CURSOR>>>"
        .. request.ps_chunk.suffix

    local builder = HarmonyRawFimPromptBuilder.new()
        :developer(developer_message)
        :user(context_lines)
        :user(fim_user_message)
        :set_thinking()
        :start_assistant_final_response() -- this forces the model to respond w/o any further thinking

    return builder:build_raw_prompt()
end

---@param request OllamaFimBackend
function M.gpt_oss.get_fim_chat_messages(request)
    -- FYI! gptoss w/ /v1/chat/completions is on hold... I am testing a raw prompt where I can disable thinking entirely (above)!

    local system_prompt = "Your response will be used for code completion in neovim"
        .. ", in a FIM (fill-in-the-middle) pluging that genrates code as the user types. \n"
        .. "Reasoning: low"
    -- .. "\nReasoning: high"
    -- .. "Reasoning: medium"

    local messages = {
        { role = "system", content = system_prompt }
    }

    -- -- * CONTEXT
    -- local context = request.context
    -- -- FYI uncomment this when READY, it's all patched up:
    -- if context.includes.yanks and context.yanks then
    --     table.insert(messages, ChatMessage:user(context.yanks.content))
    -- end
    -- if request.context.includes.matching_ctags and request.context.matching_ctags then
    --     table.insert(messages, ChatMessage:user(request.context.matching_ctags))
    -- end
    -- if context.includes.project and context.project then
    --     vim.iter(context.project)
    --         :each(function(value)
    --             table.insert(messages, ChatMessage:user(value.content))
    --         end)
    -- end
    -- TODO! review the following for changes to other usages of rag_matches before adding it back... I did update this for base0 but there might other differences since commenting it out
    -- local rag_matches = request.rag_matches
    -- if enable_rag and rag_matches ~= nil and #rag_matches > 0 then
    --     rag_message_parts = {}
    --     if #rag_matches == 1 then
    --         heading = "# RAG query match: \n"
    --     elseif #rag_matches > 1 then
    --         heading = "# RAG query matches: " .. #rag_matches .. "\n"
    --     end
    --     table.insert(rag_message_parts, heading)
    --     vim.iter(rag_matches)
    --         :each(function(chunk)
    --             -- FYI this comes from embeddings query results... so the structure is different than other context providers
    --             -- include the line number range so if there are multiple matches it might be a bit more obvious that these are subsets of lines
    --             ---@cast chunk LSPRankedMatch
    --             local file = chunk.file .. ":" .. chunk.start_line_base0 .. "-" .. chunk.end_line_base0
    --             local code_chunk = chunk.text
    --             table.insert(rag_message_parts,
    --                 "## " .. file .. "\n"
    --                 .. code_chunk .. "\n"
    --             )
    --         end)
    --     table.insert(messages, ChatMessage:user(table.concat(rag_message_parts, "\n")))
    -- end

    -- * FIM file
    local current_file_relative_path = request.inject_file_path_test_seam()
    if current_file_relative_path == nil then
        log:warn("current_file_name is nil")
        current_file_relative_path = ""
    end

    local fim_message = ""
    local repo_name = request:get_repo_name()

    fim_message = fim_message .. "Background info:"
        .. "\nrepository: " .. repo_name
        .. "\nfile: " .. current_file_relative_path
        .. "\n\nPlase complete the middle of the following example (do not return anything beyond the code for <<<CURSOR>>>):"
        .. "\n\n"
        -- NOTE I am not (yet) labeling sections, just put it together as a block and ask for the <<<CURSOR>>> part!
        .. request.ps_chunk.prefix
        .. "<<<CURSOR>>>"
        .. request.ps_chunk.suffix
    -- PRN should I be using fim tokens / format for the query here? I know it's not the same thing but if the model is trained on that, would that perform better (TODO find a way to quantify)

    table.insert(messages, ChatMessage:user(fim_message))

    return messages
end

M.qwen25coder = {
    sentinel_tokens = {
        -- https://huggingface.co/Qwen/Qwen2.5-Coder-14B-Instruct/blob/main/tokenizer_config.json
        fim_prefix = "<|fim_prefix|>", -- 151659
        fim_middle = "<|fim_middle|>", -- 151660
        fim_suffix = "<|fim_suffix|>", -- 151661
        -- fim_pad = "<|fim_pad|>", -- 151662
        repo_name = "<|repo_name|>", -- 151663
        file_sep = "<|file_sep|>", -- 151664

        im_start = "<|im_start|>", -- 151644
        im_end = "<|im_end|>", -- 151645
        endoftext = "<|endoftext|>", -- 151643

        -- * other tokens in logs, consider as needed:
        -- LF token         = 198 'Ċ'
        -- 151653 '<|vision_end|>'
        -- 151648 '<|box_start|>'
        -- 151646 '<|object_ref_start|>'
        -- 151649 '<|box_end|>'
        -- 151655 '<|image_pad|>'
        -- 151651 '<|quad_end|>'
        -- 151647 '<|object_ref_end|>'
        -- 151652 '<|vision_start|>'
        -- 151654 '<|vision_pad|>'
        -- 151656 '<|video_pad|>'
        -- 151650 '<|quad_start|>'

    },
}

-- TODO VERIFY if this is default set to EOT as I suspect (and even llama-server shows eos as stop type)
-- -- FYI I am not convinced this has any impact, nor is needed... EOT should be it and that is there by default AFAICT
-- M.qwen25coder.sentinel_tokens.fim_stop_tokens = {
--     -- FIM examples show setting several stop tokens
--     -- https://github.com/QwenLM/Qwen2.5-Coder/blob/main/examples/Qwen2.5-Coder-fim.py
--     --   eos_token_ids = [ 151643, 151645, 151659, 151660, 151661, 151662, 151663, 151664 ]
--     --       only extra token here: 151660  (fim_middle)
--     -- https://github.com/QwenLM/Qwen2.5-Coder/blob/main/examples/Qwen2.5-Coder-repolevel-fim.py
--     --   eos_token_ids = [    151643, 151645,     151659,     151661,  151662,    151663,   151664, ]
--     --                     endoftext, im_end, fim_prefix, fim_suffix, fim_pad, repo_name, file_sep,
--     M.qwen25coder.sentinel_tokens.endoftext,
--     TODO... also why exclude these tokens... doesn't make sense to me... unless a mistake is made and model skips EOS?!?
--     M.qwen25coder.sentinel_tokens.im_end,
--     M.qwen25coder.sentinel_tokens.fim_prefix,
--     M.qwen25coder.sentinel_tokens.fim_suffix,
--     -- M.qwen25coder.sentinel_tokens.fim_pad, -- shows as null in llama-cpp request body verbose output?!
--     M.qwen25coder.sentinel_tokens.repo_name,
--     M.qwen25coder.sentinel_tokens.file_sep,
-- }

---@param request OllamaFimBackend
function M.qwen25coder.get_fim_prompt(request)
    -- FYI! see fim.md for extensive FIM notes
    local tokens = M.qwen25coder.sentinel_tokens

    -- TODO confirm qwen2.5coder has trailing \n after repo_name
    --   I see this in the example files: https://github.com/QwenLM/Qwen2.5-Coder/blob/f20915b77910de5ba8463547e7654beb056ec7d0/examples/Qwen2.5-Coder-repolevel-fim.py
    --   it might not matter?
    local repo_name = request:get_repo_name()
    local prompt = tokens.repo_name .. repo_name .. "\n"

    -- * FIM file
    local current_file_relative_path = request.inject_file_path_test_seam()
    if current_file_relative_path == nil then
        -- i.e. if :new and before first :w (save)
        -- for now just leave filename blank?
        --  or, maybe mark it as new?
        --   can I deterine filetype using some heuristic or other metadata?
        --   should I mark it "new"
        log:warn("current_file_name is nil")
        current_file_relative_path = ""
    end

    --- @param context_item ContextItem
    local function append_file_non_fim(context_item)
        -- <file_sep>filepath0\ncode0
        local non_fim_file = tokens.file_sep .. context_item.filename .. "\n"
            .. context_item.content
        prompt = prompt .. non_fim_file
    end

    local instructions = ContextItem:new("instructions", [[
General project code rules:
- Never add comments to the end of a line.
- NEVER add TODO comments for me.
]])
    append_file_non_fim(instructions)

    if request.context.includes.yanks and request.context.yanks then
        append_file_non_fim(request.context.yanks)
    end

    if request.context.includes.matching_ctags and request.context.matching_ctags then
        append_file_non_fim(request.context.matching_ctags)
    end

    if request.context.includes.project and request.context.project then
        vim.iter(request.context.project)
            :each(append_file_non_fim)
    end

    if request.rag_matches then
        vim.iter(request.rag_matches)
            :each(function(chunk)
                ---@cast chunk LSPRankedMatch
                local file_name = chunk.file .. ":" .. chunk.start_line_base0 .. "-" .. chunk.end_line_base0
                local non_fim_file = tokens.file_sep .. file_name .. "\n" .. chunk.text
                prompt = prompt .. non_fim_file
            end)
    end

    -- * recent edits
    -- local recent_changes = "Here are some recent lines that were edited by the user: "
    -- for _, change in pairs(context.edits) do
    --     local str = string.format("Line %d, Column %d: %s", change.lnum, change.col, change.line)
    --     -- todo include line/col or not?
    --     -- todo include file?
    --     recent_changes = recent_changes .. "\n" .. str
    -- end
    -- raw_prompt = recent_changes .. "\n\n" .. raw_prompt

    --
    -- TODO ESCAPE presence of any sentinel tokens? i.e. should be rare but if someone is working on LLM code it may not be!
    --
    -- FYI carefully observe the format:
    --   <file_sep><fim_prefix>filepath1\ncode1_pre<fim_suffix>code1_suf<fim_middle>code1_mid
    --   <fim_prefix> comes BEFORE filepath!
    local fim_file_contents = tokens.file_sep
        .. current_file_relative_path
        .. "\n"
        .. tokens.fim_prefix
        .. request.ps_chunk.prefix
        .. tokens.fim_suffix
        .. request.ps_chunk.suffix
        .. tokens.fim_middle

    -- WARNING: anything after <|fim_middle|> is seen as part of the completion!

    return prompt .. fim_file_contents
end

M.bytedance_seed_coder = {
    qwen_sentinels = {
        fim_stop_tokens_from_qwen25_coder = {
            -- observed these generaeted by Seed-Coder:
            M.qwen25coder.sentinel_tokens.endoftext, -- stops on this
            M.qwen25coder.sentinel_tokens.file_sep, -- rambles past this, so a good stop point... rambles b/c of repeating file pattern
            "<|end|>", -- bytedance_seed_coder stops on this at times too, not sure this is a qwen25coder token...

            -- haven't seen Seed-Coder generate these but they don't hurt to add:
            M.qwen25coder.sentinel_tokens.im_end,
            M.qwen25coder.sentinel_tokens.fim_prefix,
            M.qwen25coder.sentinel_tokens.fim_suffix,
            M.qwen25coder.sentinel_tokens.repo_name,
        },
    },
    sentinel_tokens = {
        fim_suffix = "<[fim-suffix]>", --
        fim_prefix = "<[fim-prefix]>", --
        fim_middle = "<[fim-middle]>", --
        --
        -- TODO update rest from:
        -- https://huggingface.co/ByteDance-Seed/Seed-Coder-8B-Base/blob/main/tokenizer_config.json
        -- {'bos_token': '<[begin▁of▁sentence]>', 'eos_token': '<[end▁of▁sentence]>', 'sep_token': '<[SEP▁TOKEN]>', 'pad_token': '<[PAD▁TOKEN]>'}
        --
        -- TODO!!!!!! THEIR TECHINCAL PAPER SAYS THEY USED REPO LEVEL training data.... WHAT WAS THE FORMAT!!!! did it have tokens too.. it had to have a filename at least?
        --   https://arxiv.org/abs/2506.03524
        --     "repository-level variant preserved the project structure, enabling more coherent long-context learning"
        --     "Each repository was mapped to a single string sequence"
        --     "with exceptionally large repositories (e.g., PyTorch) being decomposed into multiple independent subgraphs"
        --     RepoCoder:
        --     - Seed-Coder paper refers to a microsoft research project called RepoCoder, which basically has RAG to find relevant code (repo level) and then prepends it commented out
        --     - https://github.com/microsoft/CodeT/tree/main/RepoCoder
        --     - PromptBuilder is key part, shows format used for retrieved code samples:
        --        https://github.com/microsoft/CodeT/blob/35f54d60b152cc31d134b788e702878ad613d9f7/RepoCoder/build_prompt.py#L24-L84
        --     - by the way RepoCoder primarily tested a two stage retrieve + gen process... whereby the model gets a second pass to generate the code after seeing the first pass
        --   FYI I put the format below to try out
        --     - just a hypothesis that Seed-Coder's repo level training data used the same/similar format... or something else amenable b/c they refer to the eval in the SeedCoder paper and link to RepoCoder for that
        --
        --
        -- repo_name = "<|repo_name|>", --
        -- file_sep = "<|file_sep|>", --
        --
        -- 0: <[begin▁of▁sentence]>
        -- 1: <[PAD▁TOKEN]>
        -- 2: <[end▁of▁sentence]>
        -- 3: <[UNK_never_used_51bce0c785ca2f68081bfa7d91973934]>
        -- 4: <[CLS_never_used_51bce0c785ca2f68081bfa7d91973934]>
        -- 5: <[MASK_never_used_51bce0c785ca2f68081bfa7d91973934]>
        -- 6: <[SEP▁TOKEN]>
        -- 7: <[PLHD7_never_used_51bce0c785ca2f68081bfa7d91973934]>
        -- 8: <[PLHD8_never_used_51bce0c785ca2f68081bfa7d91973934]>
        -- 9: <[PLHD9_never_used_51bce0c785ca2f68081bfa7d91973934]>
        -- 10: <[PLHD10_never_used_51bce0c785ca2f68081bfa7d91973934]>
        --
        --
        -- endoftext = "<|endoftext|>", --

        -- * other tokens in logs, consider as needed:

    },
}

---@param request OllamaFimBackend
function M.bytedance_seed_coder.get_fim_prompt_file_level_only(request)
    -- FYI file level works well for Seed-Coder

    local tokens = M.bytedance_seed_coder.sentinel_tokens
    -- * SPM
    local file_level_prompt_only = ''
        -- PRN show FIM file path commented out?
        -- tokens.file_sep
        -- .. current_file_relative_path
        -- .. "\n"
        --
        -- fyi, no newlines
        .. tokens.fim_suffix
        .. request.ps_chunk.suffix
        .. tokens.fim_prefix
        .. request.ps_chunk.prefix
        .. tokens.fim_middle

    return file_level_prompt_only
end

---@param request OllamaFimBackend
function M.bytedance_seed_coder.get_fim_prompt_repo_level(request)
    -- FYI this is NOT working well! not yet anyways!
    --    gotta find the format they trained with, for multiple files (repo level training data)

    -- FYI! see bytedance_seed_coder_notes.md
    local tokens = M.bytedance_seed_coder.sentinel_tokens
    -- TLDR => issues with stop_token... rambles endlessly so this format must not be that close too what was trained
    --   whereas some initial testing with file_sep showed it was stopping (only issue was stop token / text changed a few times but it stopped)
    --   NEXT UP... go back to qwen25coder format and try that

    local comment = ''
    if vim.bo.filetype == "python" then
        comment = '# '
    elseif vim.bo.filetype == "lua" then
        comment = '-- '
    else
        error(" only lua and python supported for RepoCoder FIM at this time")
    end

    local seperator = comment .. ('_'):rep(50) .. '\n'
    -- it would 100% make sense to have a separator token instead of 50 dashes!

    local any_repo_files = false
    local repo_files = {
        -- FYI use explicit \n so there's no mistake on concat
        comment .. "Here are some relevant code fragments from other files of the repo:\n",
        seperator,
    }

    --- @param context_item ContextItem
    local function append_file_non_fim_RepoCoder(context_item)
        any_repo_files = true
        local lines = vim.split(context_item.content, '\n')
        -- FYI would need to adjust comment format to be language specific!
        local commented_out_content = vim.iter(lines)
            :map(function(line)
                return comment .. line
            end)
            :join("\n")

        vim.list_extend(repo_files, {
            comment .. 'the below code fragment can be found in:\n',
            comment .. context_item.filename .. "\n",
            seperator,
            commented_out_content,
            seperator,

            -- TODO change to # too?
        })
    end

    if request.context.includes.yanks and request.context.yanks then
        append_file_non_fim_RepoCoder(request.context.yanks)
    end

    if request.context.includes.matching_ctags and request.context.matching_ctags then
        append_file_non_fim_RepoCoder(request.context.matching_ctags)
    end

    if request.rag_matches then
        vim.iter(request.rag_matches)
            :each(function(chunk)
                ---@cast chunk LSPRankedMatch
                local file_name_with_line_range = chunk.file .. ":" .. chunk.start_line_base0 .. "-" .. chunk.end_line_base0
                append_file_non_fim_RepoCoder({
                    filename = file_name_with_line_range,
                    content = chunk.text
                })
            end)
    end

    -- * FIM file
    local current_file_relative_path = request.inject_file_path_test_seam()
    if current_file_relative_path == nil then
        log:warn("current_file_name is nil")
        current_file_relative_path = ""
    end

    -- * SPM
    local fim_file_contents = ''
        -- PRN show FIM file path commented out?
        -- tokens.file_sep
        -- .. current_file_relative_path
        -- .. "\n"
        --
        -- fyi, no newlines
        .. tokens.fim_suffix
        .. request.ps_chunk.suffix
        .. tokens.fim_prefix
        .. request.ps_chunk.prefix
        .. tokens.fim_middle

    local prompt_lines = {}
    if any_repo_files then
        vim.list_extend(prompt_lines, repo_files)
        table.insert(prompt_lines, '"""Based on above, complete the following code:"""')
    end
    table.insert(prompt_lines, fim_file_contents)
    return table.concat(prompt_lines, "\n")
end

M.mellum = {
    -- https://huggingface.co/JetBrains/Mellum-4b-base/blob/main/special_tokens_map.json
    -- much in common with starcoder2
    sentinel_tokens = {

        -- FIM
        fim_prefix = "<fim_prefix>",
        fim_middle = "<fim_middle>",
        fim_suffix = "<fim_suffix>",
        fim_pad = "<fim_pad>",
        -- FYI file_sep => filename, repo_name => reponame... can put that back if the prompt is unique to mellum anyways
        --  but right now I suspect it will be the same as qwen25coder and starcoder2
        file_sep = "<filename>",
        repo_name = "<reponame>",

        -- roles:
        system = "<system>",
        slash_system = "</system>",
        assistant = "<assistant>",
        slash_assistant = "</assistant>",
        user = "<user>",
        slash_user = "</user>",

        think = "<think>",
        slash_think = "</think>",

        gh_stars = "<gh_stars>",

        -- PRN was base trained on commit messages? or were these just reserved for future use?
        commit_after = "<commit_after>",
        commit_before = "<commit_before>",
        commit_msg = "<commit_msg>",

        issue_start = "<issue_start>",
        issue_comment = "<issue_comment>",
        issue_closed = "<issue_closed>",

        jupyter_start = "<jupyter_start>",
        jupyter_code = "<jupyter_code>",
        jupyter_text = "<jupyter_text>",
        jupyter_output = "<jupyter_output>",
        empty_output = "<empty_output>",

        bos_token = "<|endoftext|>",
        eos_token = "<|endoftext|>",
        pad_token = "<|endoftext|>",
        unk_token = "<|endoftext|>",

    },
}

M.starcoder2 = {
    -- PRN did starcoder v1 have diff special tokens?
    sentinel_tokens = {
        -- https://huggingface.co/bigcode/starcoder2-15b/blob/main/special_tokens_map.json
        fim_prefix = "<fim_prefix>",
        fim_middle = "<fim_middle>",
        fim_suffix = "<fim_suffix>",
        fim_pad = "<fim_pad>",
        file_sep = "<file_sep>",
        repo_name = "<repo_name>",

        endoftext = "<|endoftext|>",
        issue_start = "<issue_start>",
        issue_comment = "<issue_comment>",
        issue_closed = "<issue_closed>",
        jupyter_start = "<jupyter_start>",
        jupyter_text = "<jupyter_text>",
        jupyter_code = "<jupyter_code>",
        jupyter_output = "<jupyter_output>",
        jupyter_script = "<jupyter_script>",
        empty_output = "<empty_output>",
        code_to_intermediate = "<code_to_intermediate>",
        intermediate_to_code = "<intermediate_to_code>",


        pr_start = "<pr>",
        pr_status = "<pr_status>",
        pr_is_merged = "<pr_is_merged>",
        pr_base = "<pr_base>",
        pr_file = "<pr_file>",
        pr_base_code = "<pr_base_code>",
        pr_diff = "<pr_diff>",
        pr_diff_hunk = "<pr_diff_hunk>",
        pr_comment = "<pr_comment>",

        pr_event_id = "<pr_event_id>",
        pr_review = "<pr_review>",
        pr_review_state = "<pr_review_state>",
        pr_review_comment = "<pr_review_comment>",
        pr_in_reply_to_review_id = "<pr_in_reply_to_review_id>",
        pr_in_reply_to_comment_id = "<pr_in_reply_to_comment_id>",

        pr_diff_hunk_comment_line = "<pr_diff_hunk_comment_line>",

        -- "<NAME>",
        -- "<EMAIL>",
        -- "<KEY>",
        -- "<PASSWORD>"
    }
}

function M.mellum.get_fim_prompt(request)
    -- FYI! see test case for mellum, I have a bunch of notes over there
    local tokens = M.mellum.sentinel_tokens

    -- * repo_name
    local repo_name = request.get_repo_name()
    local prompt = tokens.repo_name .. repo_name

    --- @param context_item ContextItem
    local function append_file_non_fim(context_item)
        -- <filename>filepathX\ncodeX
        local non_fim_file = tokens.file_sep .. context_item.filename .. "\n" .. context_item.content
        prompt = prompt .. non_fim_file
    end

    -- * recent yanks
    if request.context.includes.yanks and request.context.yanks then
        append_file_non_fim(request.context.yanks)
    end

    -- * FIM file
    local current_file_path = request.inject_file_path_test_seam()
    if current_file_path == nil then
        log:warn("current_file_name is nil")
        current_file_path = ""
    end
    --
    -- TODO ESCAPE sentinal tokens?
    --
    -- FYI carefully observe the format:
    --     <filename>example.py
    --     <fim_suffix>
    --
    --     # Test the function
    --     result = calculate_sum(5, 10)
    --     print(result)<fim_prefix>def calculate_sum(a, b):
    --     <fim_middle>"""
    local fim_file_contents = tokens.file_sep
        .. current_file_path
        .. "\n"
        .. tokens.fim_suffix
        .. request.suffix
        .. tokens.fim_prefix
        .. request.prefix
        .. tokens.fim_middle

    prompt = prompt .. fim_file_contents

    -- WARNING: anything after <|fim_middle|> is seen as part of the completion!


    -- alt format example
    -- f"<fim_suffix>{suffix}<fim_prefix>{prefix}<fim_middle>"


    return prompt
end

function M.starcoder2.get_spm_fim_prompt(request)
    -- TODO look into setting STOP token... I am noticing it often goes on for a very long time, endlessly
    -- esp in these comments and in test case code

    -- TODO add support for SPM (also)...
    -- investigate perf differences
    -- i.e. kv cache impact
    --
    -- StarCoder2 supports both:
    --   https://github.com/bigcode-project/starcoder2/issues/14   --
    --   was trained on 50/50
    --   IIRC so was Qwen2.5-Coder?
    --     TODO investigate if Qwen2.5-Coder supports SPM
end

function M.starcoder2.get_fim_prompt(request)
    -- FYI! see notes in starcoder2.md

    -- <repo_name>reponame<file_sep>filepath0\ncode0<file_sep><fim_prefix>filepath1\ncode1_pre<fim_suffix>code1_suf<fim_middle>code1_mid<file_sep> ...<|endoftext|>
    -- TODO <|endoftext|> to stop tokens? must already be set IIGC cuz I get completions that terminate appropriately, quite often
    --   TODO add <file_sep> to STOP tokens?
    --      https://github.com/bigcode-project/starcoder2/issues/10#issuecomment-2214157190
    --      is it already setup that way?
    local tokens = M.starcoder2.sentinel_tokens

    -- * repo_name
    -- TODO confirm repo naming? is it just basename of repo root? or GH link? or org/repo?
    local repo_name = request.get_repo_name()
    local prompt = tokens.repo_name .. repo_name

    --- @param context_item ContextItem
    local function append_file_non_fim(context_item)
        -- <file_sep>filepath0\ncode0
        local non_fim_file = tokens.file_sep .. context_item.filename .. "\n" .. context_item.content
        prompt = prompt .. non_fim_file
    end

    -- * recent yanks
    if request.context.includes.yanks and request.context.yanks then
        append_file_non_fim(request.context.yanks)
    end

    -- * FIM file
    local current_file_path = request.inject_file_path_test_seam()
    if current_file_path == nil then
        log:warn("current_file_name is nil")
        current_file_path = ""
    end
    --
    -- TODO ESCAPE presence of any sentinel tokens? i.e. should be rare but if someone is working on LLM code it may not be!
    --
    -- FYI carefully observe the format:
    --   <file_sep><fim_prefix>filepath1\ncode1_pre<fim_suffix>code1_suf<fim_middle>code1_mid
    --   <fim_prefix> comes BEFORE filepath!
    local fim_file_contents = tokens.fim_prefix
        .. current_file_path
        .. "\n"
        .. request.prefix
        .. tokens.fim_suffix
        .. request.suffix
        .. tokens.fim_middle


    -- WARNING: anything after <|fim_middle|> is seen as part of the completion!

    return prompt .. tokens.file_sep .. fim_file_contents
end

M.codestral = {
    -- https://docs.mistral.ai/capabilities/code_generation/
    -- by the way this repo might have reference templates for several models
    --   https://github.com/continuedev/continue/blob/main/core/llm/templates/edit/codestral.ts#L1
    --
    --
    -- TODO try codestra-2501 via API - s/b a material update to codestral 2405 (IIRC, 2024)
    --   watch for a release of it
    -- TODO try mamba-codestral via API (or its on hf and should work w/ mlx but can't figure it out yet)
    -- TODO devstral, can it do FIM?


    sentinel_tokens = {
        -- TODO is there a paper?
        -- only references I can find so far:
        --   * https://huggingface.co/mistralai/Codestral-22B-v0.1/blob/main/tokenizer_config.json
        --   https://huggingface.co/mistralai/Codestral-22B-v0.1/blob/main/special_tokens_map.json
        --   [PREFIX]
        fim_prefix = "[PREFIX]",
        fim_middle = "[MIDDLE]",
        fim_suffix = "[SUFFIX]",

        bos_token = "<s>",
        eos_token = "</s>",
        unk_token = "<unk>",

    },

}

function M.codestral.get_fim_prompt(request)
    local tokens = M.codestral.sentinel_tokens

    -- TODO! VERIFY THE FORMAT!!!! this is just a GH issue that suggested it
    -- found suggestion:
    --   https://github.com/ollama/ollama/issues/5403
    --   <s>[SUFFIX] {{ suffix }} [PREFIX] {{ prefix }}
    --    TODO this doesn't include [MIDDLE]... should I add it?
    -- TODO! try PSM format next... sometimes in calc.lua I am getting [SUFFIX] on end of response!
    local fim_file_contents = tokens.fim_suffix
        .. request.suffix
        .. tokens.fim_prefix
        .. request.prefix
        .. tokens.fim_middle -- TODO! find out about MIDDLE? completions work well enough w/ and w/o this

    -- TODO filename, multi-file, etc?
    return fim_file_contents
end

M.deepseek_coder_v2 = {
    -- https://github.com/deepseek-ai/DeepSeek-Coder-V2
    -- https://github.com/deepseek-ai/DeepSeek-Coder-V2?tab=readme-ov-file#code-insertion
    --  "lite" == 16B size
    --    * AFAICT only lite has FIM
    --  base = FIM  /  instruct = chat
    -- ** FAST MoE
    -- 217 TPS! first load OMFG
    -- model = "deepseek-coder-v2:16b-lite-base-q8_0", # **** 217 TPS!
    -- model = "deepseek-coder-v2:16b-lite-base-fp16" # TODO TRY THIS ONE
    -- TODO can I get fp in memory?!

    sentinel_tokens = {
        --
        -- FYI it's not spaces around the pipe char:
        fim_begin = "<｜fim▁begin｜>",
        fim_hole = "<｜fim▁hole｜>",
        fim_end = "<｜fim▁end｜>",

        -- TODO what name for this?
        fim_stop_tokens = { "<|eos_token|>" }
    }

}

-- input_text = """<｜fim▁begin｜>def quick_sort(arr):
--     if len(arr) <= 1:
--         return arr
--     pivot = arr[0]
--     left = []
--     right = []
-- <｜fim▁hole｜>
--         if arr[i] < pivot:
--             left.append(arr[i])
--         else:
--             right.append(arr[i])
--     return quick_sort(left) + [pivot] + quick_sort(right)<｜fim▁end｜>"""

function M.deepseek_coder_v2.get_fim_prompt(request)
    local tokens = M.deepseek_coder_v2.sentinel_tokens

    -- PSM format:
    -- <｜fim_begin｜> 𝑓𝑝𝑟𝑒<｜fim_hole｜> 𝑓𝑠𝑢 𝑓<｜fim_end｜> 𝑓𝑚𝑖𝑑𝑑𝑙𝑒<|eos_token|>
    local fim_file_contents = tokens.fim_begin
        .. request.prefix
        .. tokens.fim_hole
        .. request.suffix
        .. tokens.fim_end

    return fim_file_contents

    -- ** paper also says at "document level" ...
    -- * can I include fileanme? (if so => yanks/edits/etc)
    -- * multiple files?
    -- return prompt .. tokens.file_sep .. fim_file_contents
end

return M
