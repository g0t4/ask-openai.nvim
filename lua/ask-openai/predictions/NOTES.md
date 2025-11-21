## Predictions notes

- Obviously, short files do really well
    - Long files can be a challenge to get the right context

## Chat Based FIM with gpt-oss

- Reasoning effort:
  - described in: https://cdn.openai.com/pdf/419b6906-9da6-406c-a19d-1bb078ac7637/oai_gpt-oss_model_card.pdf
  - add to System Prompt with "Reasoning: high" (high medium low)
  - FYI seems to be tied to complexity of the code you are FIM'ing too... went faster for shorter code inputs (not b/c of input processing time but literally I watched thinking time take longer)

"prompt": "I need you to fill-in-the-middle of the following code (FIM)... do not generate anything but the code at <GAP> def fib(n):\n    \"\"\"Return the nth Fibonacci number.\"\"\"\n    # <GAP>\n    return\n",
"temperature": 0.0,
"max_tokens": 128,

## TODOs

- Provide recent edits to current code 100% will improve suggestions when making changes
    i.e. if I start rewriting code, I want it to know what it looked like a moment ago...
    I have found rewriting alone causes friction but if I comment out the old code (i.e. below) and start to rewrite it above it then it uses that as a reference for the new code
    so, if it had recent edits I think this would be implicit
- Find a way to rewrite the rest of the current line...
    how about just hide remainder of line and show new line ending?
- Provide symbols from coc completions to model as inputs too?
    smth like:
    `:echo CocAction('documentSymbols')`
    `:echo CocAction('documentSymbols')->filter({_, s -> CocAction('getCursor')[0] >= s.range.start.line && CocAction('getCursor')[0] <= s.range.end.line })`
       fix getCursor, it doesn't exist
    - Have an option to toggle sending symbols! let the user decide!
- WIP (avoid truncating prompt)
    - TODO => if I have to build custom Modelfiles per model... I'd rather just go back to /api/generate and not deal with the custom models nonsense
        - TODO try that and see if that truly allows me to customize all parameters I care about
        - i.e. num_ctx
    - TODO also need to set PARALLEL env var... can that be done via /api/generate and a parameter?
        - IF NOT, just use ENV VAR
        - FYI OLLAMA_NUM_PARALLEL maps to llama-server's --parallel 1  # arg
        - OH WOW, parallel 1 takes LESS MEMORY! for caching, etc... I bet I can fit a bigger model in GPU memory now!
            - TODO verify if that is the case
    - PRN add token size estimation (or actually check embedding and adjust prompt?)... is that heavy (per request, what is overhead ms?)...
        - if not, stick to estimation based on # chars or otherwise
        - see llm-ls for how it handles this as it had choices IIRC


    - creativity? vs strictness?
    - review API docs for ollama for what can be passed (also look at llama.cpp and openai's /v1/completions)
- Stop generating further prediction tokens... but also don't exit to normal mode
    - OR, maybe keep prediction even in normal mode! and allow accepting it?
        - Esc is a potent way to stop it... that feels right at home...
        - would avoid yet another keybinding!
        - would have to remove code to trigger on insertenter and insertleave
- ollama - make sure model loads even if first request is canceled...
    - currently, if model is not loaded, the first request has to go through for the model to fully load
    - if first request is canceled (i.e. b/c I am typing)... the serve repeatedly spasms runner starts and terminates runner
    - can server not terminate runner on request cancel?! just let it run anyways?

- include outline/symbols for current doc
    - include symbols "in-scope" of cursor position!
- include recent edits? (other files too) and maybe the symbol edited (i.e. func)
    - filter other file edits based on type? or just give all?
        - i.e. if I edit markdown files, will I really need that if I switch to lua (i.e. this notes file)
    - perhaps add a diff keymap that expands the context if I don't get what I want with a default context
- include preamble request of what to do? <|im_start|> section?
- Test other backends:
    - llama-server
    - vllm - https://docs.vllm.ai/en/latest/getting_started/installation/gpu/index.html?device=rocm

- TODO strip comments? or maybe strip comments marked a certain way? or not marked that way?
### Observations todo

- Comments are essential in complicated scenarios, even a simple single word can make the model do it all right!

- generated an ending comment to offset the filename comment_header... and then it started to explain the changes in markdown prefix/suffix
    - maybe try im_start/end before
    - OR, <|file_sep|> instead?
- scrolling paste cursor position moves cursor and fubars the prediction, maybe not end of world but...
    - might also be nice to scroll around before accepting it!


### Context to send


- Send symbols/api of all require'd modules (lang specific)
    - so, any lua objects I have imported
    - maybe even give type / signatures of all in-scope variables?!
        - now that would be where the LS comes in!
    - probably overkill
- Select based on syntax tree? vim.treesitter
    - vim.treesitter.get_node_text(vim.treesitter.get_node(),0) -- text of current node
    - perhaps try to take N lines before/after and only if that's not enough, then use syntax tree (if avail)
        - perhaps N lines of "current" tree context! (don't have to make before/after symmetric)
            - though, FIM training was symmetric (1/3 of doc)... not sure that means anything
    - lua:
        - nearest function body (above current point)
            - or, detect top level function body (if enough room in context)
        - or, if in top level `chunk` then grab lines based on entire nodes before/after
    - then, include symbols that are "in scope" at cursor position (but outside of lines that are sent)
        - maybe even mention symbols before/after in current file
        - also, workspace symbols that are in-scope?
- Only send prior lines and ask for AR completion, instead of FIM?
    - add special keymap for this?
    - if I like this as an alternative, I could have a mode to toggle FIM/AR
    - quite often this is all you need, esp if writing a function body with nothing after it but the rest of the file
- recent edits (esp symbols, i.e. of a function edited in another file)
    - `:changes` keeps track of change history, across restarts too!
    - this is where using the syntax tree might be really helpful to limit the scope of what to include in the edit history
    - `InsertTextChangedI`? already using this to trigger predictions
        - capture changes when the event fires?
        - would want a way to get high level overview of edits like :changes and not save every char typed
        - clearly, :changes doesn't track every typed char, it seems to be PER LINE?
            - ok use events and when a line changes add that, and if that same line changes next then consolidate that with all edits to that line until new line edited
    - changes are per file...
        - how would I track across files, use open files/buffers?
    - `:undolist`? too?
        - FYI `undofile` option to save/restore undo history across restarts (normally off)
    - maybe verbatim just dump :changes and :undolist into the prompt?
    - `treesitter`:
        - `:h LanguageTree:register_cbs()`
            - `on_changedtree`

- clipboard contents (nice to have) and probably a waste of space? maybe some sort of detection if its code and if so then include it?
- It might be nice to allow the model to request additional context... i.e. not send clipboard all the time, just when it may be relevant
- let user indicate expand context (i.e. re-request but with bigger context -- like the next scope above, all of its code)
- File name
    - keep it in a comment in the prefix?
    - or, pass it in a separate file before FIM?
- pass repo (project name) token
- pass file name as a file separator token?
    - create some test code examples that are ambiguous without file name (similar languages) and see how it does w/ and w/o the name

### Post processing

- If repeating start of suffix is inevitable, can I add some sort of detection of that repeat and exclude the duplicated lines that overlap at the end of the suggestion? Only do this if you can't find a different way to mititage the occurences b/c this would be a bit of work to show/hide the suggestion as it arrives (chunk by chunk)  could cause spasming display if there is temporarily some overlap and then another chunk breaks the overlap and maybe later again adds more... hard to say this is the best way? Maybe once full completion arrives you can do this check and then hide the duplicate part, but let it all stream back as-is?

### Prompting?

- Things to guide it:
    - No markdown if not a markdown file
    - Comments have to be valid (not just willy nilly text) =>  esp happens w/ new files that have maybe one comment at the top, it thinks its time to write a guide doc with text and code
- Comments work well (as is expected)
- How about when there's a db schema... include it when relevant or always or?
    - i.e. usaspending db/repo... would rock to have that context when writing a sql query! there we go... if working in a sql file we include the repo level sql prompt!


### Tool use?

- How about allow the model to request more data (i.e. read a file for a given symbol?)... what could that look like? Qwen has tool use BTW

### Rewrite the Middle

- Not just FIM, also RIM!
    - idea => mark a section inside the FIM that can be rewritten, basically whatever is replaced in that section will become the prediction and I can diff it with that same section to show it then
    - use vim.diff?
- As far as formatting/prompting...
    - can I get away w/o fine tuning or training a model on the new "<|rewrite_start|>" and "<|rewrite_end|>" and just use them with a good prompt somewhere?
    - I fixed that prompt for Zed with local models and it started working really well... why not try using that one for what I wanna do here...
    - Also wish I could get a model to generate diffs of changes but not sure that will work well, more testing is needed
        - someone should train some models on generating diffs instead of regurgitate entire chunk of text...
            - or smth more like fast edit model in Zed w/ Claude Sonnet, can this be used in local models?
- Examples
    - Like Zed's predictions
    - And, supermaven has this for:
        - rewrite current line (fill in multiple spots basically)
        - jump edits
        -

### Ux of completion

- reject current line (discard it)? i.e. to take the next line
- run formatter on accept (of just what was added and only if code "compiles")
- run formatter before showing prediction and see if the formatter succeeds then use that instead of the prediction?

## model testing

- benchmarks to establish realistics expectations for tokens/sec etc..
    - https://github.com/XiongjieDai/GPU-Benchmarks-on-LLM-Inference
- qwen2.5-coder
    - 7b-base-Q8_0 didn't seem to work as well or generated less code?

## truncate context warning

- Truncated context due to num_ctx being too small... using a Modelfile to adjust
    - warning that hints at this "misconfiguration" ... if you want parallelism then n_ctx_train (total possible context) is sliced up into smaller chunks, but I don't want that (not yet)
        llama_new_context_with_model: n_ctx_per_seq (2048) < n_ctx_train (32768) -- the full capacity of the model will not be utilized
    - warning that tells you it happened for a given prompt
        level=WARN source=runner.go:129 msg="truncating input prompt" limit=2048 prompt=2694 keep=4 new=2048
    - Considerations:
        - can set num_ctx and parallelism when starting ollama serve
            - `OLLAMA_CONTEXT_LENGTH=8192` => `n_ctx`
            - `OLLAMA_NUM_PARALLEL=1` => `n_seq_max`
            - `n_ctx_per_seq` = `n_ctx / n_seq_max`
            - n_ctx_train (max context the model supports)
      or, can make a new Modelfile and alter model's defaults
- how does RoPE scaling factor (for positional embeddings using tuned theta) into n_ctx?
   - ollama has n_ctx_train = 32K (is this actually the size or is it 128K?)


## llama-server final SSE differences

- includes stats, input params

{
  "index": 0,
  "content": "",
  "tokens": [],
  "id_slot": 0,
  "stop": true,
  "model": "qwen2.5-coder:7b-instruct-q8_0",

  "tokens_predicted": 7,
  "tokens_evaluated": 53,

  "generation_settings": {
    "n_predict": -1,
    "seed": 4294967295,
    "temperature": 0.800000011920929,
    "dynatemp_range": 0.0,
    "dynatemp_exponent": 1.0,
    "top_k": 40,
    "top_p": 0.949999988079071,
    "min_p": 0.05000000074505806,
    "top_n_sigma": -1.0,
    "xtc_probability": 0.0,
    "xtc_threshold": 0.10000000149011612,
    "typical_p": 1.0,
    "repeat_last_n": 64,
    "repeat_penalty": 1.0,
    "presence_penalty": 0.0,
    "frequency_penalty": 0.0,
    "dry_multiplier": 0.0,
    "dry_base": 1.75,
    "dry_allowed_length": 2,
    "dry_penalty_last_n": 32768,
    "dry_sequence_breakers": [
      "\n",
      ":",
      "\"",
      "*"
    ],
    "mirostat": 0,
    "mirostat_tau": 5.0,
    "mirostat_eta": 0.10000000149011612,
    "stop": [],
    "max_tokens": -1,
    "n_keep": 0,
    "n_discard": 0,
    "ignore_eos": false,
    "stream": true,
    "logit_bias": [],
    "n_probs": 0,
    "min_keep": 0,
    "grammar": "",
    "grammar_lazy": false,
    "grammar_triggers": [],
    "preserved_tokens": [],
    "chat_format": "Content-only",
    "reasoning_format": "auto",
    "reasoning_in_content": false,
    "thinking_forced_open": false,
    "samplers": [
      "penalties",
      "dry",
      "top_n_sigma",
      "top_k",
      "typ_p",
      "top_p",
      "min_p",
      "xtc",
      "temperature"
    ],
    "speculative.n_max": 16,
    "speculative.n_min": 0,
    "speculative.p_min": 0.75,
    "timings_per_token": false,
    "post_sampling_probs": false,
    "lora": []
  },
  "prompt": "<|repo_name|>ask-openai.nvim\n<|file_sep|>.ask.context\n\n<|file_sep|>lua/ask-openai/prediction/tests/calc/calc.lua\n<|fim_prefix|>local M = {}\n\nfunction M.add(a, b)\n    <|fim_suffix|>\n    return a + b\nend\n\n\n\nreturn M<|fim_middle|>",
  "has_new_line": false,
  "truncated": false,
  "stop_type": "eos",
  "stopping_word": "",
  "tokens_cached": 59,

  "timings": {
    "prompt_n": 52,
    "prompt_ms": 33.474,
    "prompt_per_token_ms": 0.6437307692307692,
    "prompt_per_second": 1553.4444643603993,
    "predicted_n": 7,
    "predicted_ms": 51.669,
    "predicted_per_token_ms": 7.381285714285714,
    "predicted_per_second": 135.47775261762374,
    "draft_n": 3,
    "draft_n_accepted": 1
  }

}

