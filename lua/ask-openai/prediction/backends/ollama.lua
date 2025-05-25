local M = {}
local log = require("ask-openai.prediction.logger").predictions()
local qwen = require("ask-openai.backends.models.qwen")
local meta = require("ask-openai.backends.models.meta")

local function body_for(prefix, suffix, current_context)
    local body = {

        -- FYI set of possible models for demoing impact of fine tune
        -- model = "qwen2.5-coder:14b-base-q8_0", -- ** shorter responses, more "EOF" focused
        model = "qwen2.5-coder:7b-base-q8_0", -- ** shorter responses, more "EOF" focused
        -- model = "qwen2.5-coder:7b-instruct-q8_0", -- longer, long winded, often seemingly ignores EOF
        --
        -- model = "codellama:7b-code-q8_0", -- shorter too
        -- model = "codellama:7b-instruct-q8_0", -- longer too
        -- model = "codellama:7b-python-q8_0", -- doesn't do well with FIM (spits out FIM tokens text as if not recognized)... also not sure it supports FIM based on reading docs only code/instruct are mentioned for FIM support)
        --
        -- model = "llama3.1:8b-text-q8_0", -- weird, generated some "code"/text in this file that wasn't terrible!... verbose
        -- model = "llama3.1:8b-instruct-q8_0", --
        -- https://github.com/meta-llama/codellama/blob/main/llama/generation.py#L496



        raw = true, -- bypass templates (only /api/generate, not /v1/completions)

        stream = true,
        num_predict = 200, -- aka max_tokens

        -- TODO temperature, top_p,

        options = {
            -- https://github.com/ollama/ollama/blob/main/docs/api.md#generate-request-with-options
            -- options only for /api/generate
            --   /v1/completions ignores them even though it uses same GenerateHandler!


            -- TODO can I pass OLLAMA_NUM_PARALLEL=1 via request?
            num_ctx = 8192,
        }
    }

    local sentinel_tokens = qwen.qwen25coder.sentinel_tokens

    if string.find(body.model, "codellama") then
        sentinel_tokens = meta.codellama.sentinel_tokens

        -- codellama uses <EOT> that seems to not be set as param in modelfile (at least for FIM?)
        --   without this change you will see <EOT> in code at end of completions
        -- ollama show codellama:7b-code-q8_0 --parameters # => no stop param
        body.options.stop = { "<EOT>" }

        -- FYI also ollama warns about:
        --    level=WARN source=types.go:512 msg="invalid option provided" option=rope_frequency_base
    elseif not string.find(body.model, "qwen2.5-coder", nil, true) then
        -- warn that FIM tokens need to be set
        log:error("PLEASE REVIEW FIM SENTINEL TOKENS FOR THE NEW MODEL! right now you are using sentinel_tokens for qwen2.5-coder")
        return
    end


    body.prompt = M.get_file_level_fim_prompt(prefix, suffix, sentinel_tokens)
    -- body.prompt = M.get_prompt_repo_style_with_context(prefix, suffix, sentinel_tokens, current_context)
    log:trace('body.prompt', body.prompt)

    local body_json = vim.json.encode(body)

    log:trace("body", body_json)

    return body_json
end

function M.get_file_level_fim_prompt(prefix, suffix, sentinel_tokens)
    log:trace("prefix", "'" .. prefix .. "'")
    log:trace("suffix", "'" .. suffix .. "'")

    -- *** File-level FIM template:
    --   <|fim_prefix|>{code_pre}<|fim_suffix|>{code_suf}<|fim_middle|>{code_mid}<|endoftext|>
    --   from Tech Report: https://arxiv.org/pdf/2409.12187
    --   official example: https://github.com/QwenLM/Qwen2.5-Coder/blob/main/examples/Qwen2.5-Coder-fim.py

    -- TODO ESCAPE presence of any sentinel tokens! i.e. should be rare but if someone is working on LLM code it may not be!

    local prompt = sentinel_tokens.fim_prefix .. prefix
        .. sentinel_tokens.fim_suffix .. suffix
        .. sentinel_tokens.fim_middle

    return prompt
end

function M.get_prompt_repo_style_with_context(prefix, suffix, sentinel_tokens, current_context)
    -- *** Repo-level + File-level FIM template:
    --   this is from the Qwen2.5-Coder Tech Paper: https://arxiv.org/pdf/2409.12186
    --   official example: https://github.com/QwenLM/Qwen2.5-Coder/blob/main/examples/Qwen2.5-Coder-repolevel-fim.py
    --
    -- <|repo_name|>{repo_name}
    -- <|file_sep|>{file_path1}
    -- {file_content1}
    -- <|file_sep|>{file_path2}
    -- {file_content2}
    -- <|file_sep|>{file_path3}
    -- <|fim_prefix|>{code_pre}<|fim_suffix|>{code_suf}<|fim_middle|>{code_fim}<|endoftext|>
    --
    -- *** StarCoder paper
    --   Qwen2.5Coder's Tech Report used this (at least for FIM)
    --   https://arxiv.org/pdf/2402.19173
    --   StarCoder paper
    --
    --    *** test below scenarios standalone too (practice format, see what mistakes you make, understand when useful)
    --
    --   <repo_name>reponame<file_sep>filepath0\ncode0<file_sep><fim_prefix>filepath1\ncode1_pre<fim_suffix>code1_suf<fim_middle>code1_mid<file_sep> ...<|endoftext|>
    --      StarCoder2 doesn't include new line after reponame/filepathX, basically only between filepath\ncode...
    --      also means when no filepaths included then there are no new lines at all
    --      BUT, qwen examlpes show new lines:
    --        https://github.com/QwenLM/Qwen2.5-Coder/blob/main/examples/Qwen2.5-Coder-repolevel-fim.py
    --
    --   TODO give full path to file (relative to repo root?)
    --
    --   <file_sep>code1<file_sep>code2 ... <|endoftext|>.
    --     50% of time repo metadata not included (no repo name, no file paths)..
    --     TODO! try w/o repo name AND file paths
    --
    --   StarCoder2 paper also used these sentinels:
    --      see Table 5
    --        <issue_[start|comment|closed]>
    --        <pr>,<pr_[status|is_merged|base|file|base_code|diff|diff_hunk|comment|event_id|review|review_state|in_reply_to_review_id|in_reply_to_comment_id|diff_hunk_comment_line]>
    --        <jupyter_[start|text|code|output|script]>,<empty_output>
    --        <code_to_intermediate>, <intermediate_to_code>
    --     Q2.5C Tech Report mentions:  "In addition to raw code, we also collected data from Pull Requests, Commits, Jupyter Notebooks, and Kaggle datasets, all of which were subjected to similar rule-based cleaning techniques."
    --       did qwen also use <issue_/<pr_/<jupyter_/etc tags?
    --       <jupyter might give me a new way to express code gen requests!

    --
    --  TODO! try starcoder2 (and variants?)
    --     https://ollama.com/library/starcoder2/tags
    --  TODO design with full file contents only?
    --  - if it was trained on full files from repo (except last one), then IIAC model will do best with full files
    --  - TODO what if I fed in relevant files (i.e. require'd/chain)? can have toggle to flip this if it gets to be too many tokens
    --      TEST how this performs for cross file FIM
    --  - TODO redesign context in terms of a full file...
    --      i.e. name a simple `notes.md` file?
    --      `outline.md` could house current coc completions in a way to make it look like just an outline?
    --        how about feed all global symbols in? in addition to those in current context?
    --      a clipboard file name? for yanks clipboard-1
    --
    --  - TODO how many tokens are some of my current repos/subsets (i.e. my nvim config, hammerspoon, ask-openai plugin... ) how slow is it to give it all linked files at least if not all?!
    --

    -- MISC:
    -- - Tech Report mentions: Since too many instruction samples without code snippets hurt the model performance on code generation tasks (e.g. MultiPL-E, McEval, and MdEval), we remove most of the samples without code snippets to keep the code generation capability of our instruction model.
    --    is it that perf is inversely affected by comments?
    --    OR is it just when there is very little / no code at all?
    --    TODO should I not be including comments if they go over a threshold?! argh I love notes in code

    -- *** Repo-level "Completions"?
    --   no FIM for the last file... just file level completion (remainder of file)... like having no suffix
    --   this is from the Qwen2.5-Coder Tech Paper: https://arxiv.org/pdf/2409.12186
    --   official example: https://github.com/QwenLM/Qwen2.5-Coder/blob/main/examples/Qwen2.5-Coder-repolevel.py
    --   example is also in readme: https://github.com/QwenLM/Qwen2.5-coder?tab=readme-ov-file#4-repository-level-code-completion
    --
    -- <|repo_name|>{repo_name}
    -- <|file_sep|>{file_path1}
    -- {file_content1}
    -- <|file_sep|>{file_path2}
    -- {file_content2}
    -- <|file_sep|>{file_path3}
    -- {file_content3_prefix}
    --
    --    *** TLDR think of not having a suffix... so you only have Prefix and Middle... and I guess no need to include the FIM tokens?!
    --    is this a reliable way... if this works then does it mean there are other mods I can make that should reliably work too?
    --    i.e. to provide context another way?
    --
    --  FYI I don't think I have a need for this at all (unless someone is completing at end of a file!) even then why wouldn't PSM work w/o the suffix?

    -- Observations:
    -- - so far, repo+file-level FIM doesn't work well... 90% of predictions are "stop"/empty immediately
    --    I observed this with llama.vim plugin too!
    --    I definitely notice a diff b/w my file-level fim ONLY prompt (works very well) and this combo
    --       that said, when I developed my file-level FIM... even small mistakes led to problems / crap completions
    --       so lets make sure this is well understood and tested before I conclude anything
    --
    -- - I should do some testing in isolation to see how specific prompts behave before I coclude much about wheter or not repo+file level FIM is useful


    local repo_name = vim.fn.getcwd():match("([^/]+)$")
    local repo_prompt = sentinel_tokens.repo_name .. repo_name .. "\n"
    local context_file_prompt = sentinel_tokens.file_sep .. "nvim-context-tracking-notes.md\n"
        .. "The following notes are gathered automatically, they capture recent user activities that may help in completing FIM requests\n"
    if current_context.yanks ~= "" then
        -- TODO? format the prompt entirely here so it can differ vs plain FIM context?
        context_file_prompt = context_file_prompt .. "\n" .. current_context.yanks .. "\n\n"
    end

    local fim_file_contents = M.get_file_level_fim_prompt(prefix, suffix, sentinel_tokens)
    local current_file_name = vim.fn.expand('%'):match("([^/]+)$")
    local fim_file = sentinel_tokens.file_sep .. current_file_name .. "\n"
        .. fim_file_contents .. "\n"

    -- return repo_prompt .. context_file_prompt .. fim_file
    return repo_prompt .. fim_file
end

function M.build_request(prefix, suffix, current_context)
    local options = {
        command = "curl",
        args = {
            "-fsSL",
            "--no-buffer", -- curl seems to be the culprit... w/o this it batches (test w/ `curl *` vs `curl * | cat` and you will see difference)
            "-X", "POST",
            "http://ollama:11434/api/generate", -- TODO pass in api base_url (via config)
            "-H", "Content-Type: application/json",
            "-d", body_for(prefix, suffix, current_context),
        },
    }
    return options
end

function M.process_sse(data)
    -- SSE = Server-Sent Event
    -- split on lines first (each SSE can have 0+ "event" - one per line)

    -- FYI use nil to indicate nothing in the SSE... vs empty line which is a valid thingy right?
    local chunk = nil -- combine all chunks into one string and check for done
    local done = false
    local done_reason = nil
    for ss_event in data:gmatch("[^\r\n]+") do
        if ss_event:match("^data:%s*%[DONE%]$") then
            -- done, courtesy last event... mostly ignore b/c finish_reason already comes on the prior SSE
            return chunk, true
        end

        --  strip leading "data: " (if present)
        local event_json = ss_event
        if ss_event:sub(1, 6) == "data: " then
            -- ollama /api/generate doesn't prefix each SSE with 'data: '
            event_json = ss_event:sub(7)
        end
        local success, parsed = pcall(vim.json.decode, event_json)

        -- *** examples /api/generate:
        --    {"model":"qwen2.5-coder:3b","created_at":"2025-01-26T11:24:56.1915236Z","response":"\n","done":false}
        --  done example:
        --    {"model":"qwen2.5-coder:3b","created_at":"2025-01-26T11:24:56.2800621Z","response":"","done":true,"done_reason":"stop","total_duration":131193100,"load_duration":16550700,"prompt_eval_count":19,"prompt_eval_duration":5000000,"eval_count":12,"eval_duration":106000000}
        if success and parsed and parsed.response then
            if parsed.done then
                done_reason = parsed.done_reason
                done = true
                if done_reason ~= "stop" then
                    log:warn("WARN - unexpected /api/generate done_reason: ", done_reason, " do you need to handle this too?")
                    -- ok for now to continue too
                end
            end
            chunk = (chunk or "") .. parsed.response
        else
            log:warn("SSE json parse failed for ss_event: ", ss_event)
        end
    end
    -- TODO test passing back finish_reason (i.e. for an empty prediction log entry)
    return chunk, done, done_reason
end

return M
