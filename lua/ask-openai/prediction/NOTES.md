## Predictions notes

- Obviously, short files do really well
    - Long files can be a challenge to get the right context

## TODOs

- Look into model params
    - in some cases context is truncated... I wonder if this is when I felt like part of prompt was ignored... see ollama logs
        level=WARN source=runner.go:129 msg="truncating input prompt" limit=2048 prompt=2694 keep=4 new=2048
    - creativity? vs strictness?
    - review API docs for ollama for what can be passed (also look at llama.cpp and openai's /v1/completions)
- Stop generating further prediction tokens... but also don't exit to normal mode
    - OR, maybe keep prediction even in normal mode! and allow accepting it?
        - Esc is a potent way to stop it... that feels right at home...
        - would avoid yet another keybinding!
        - would have to remove code to trigger on insertenter and insertleave

- include outline/symbols for current doc
    - include symbols "in-scope" of cursor position!
- include recent edits? (other files too) and maybe the symbol edited (i.e. func)
    - filter other file edits based on type? or just give all?
        - i.e. if I edit markdown files, will I really need that if I switch to lua (i.e. this notes file)
    - perhaps add a diff keymap that expands the context if I don't get what I want with a default context
- include preamble request of what to do? <|im_start|> section?

- TODO strip comments? or maybe strip comments marked a certain way? or not marked that way?
### Observations todo
- generated an ending comment to offset the filename comment_header... and then it started to explain the changes in markdown prefix/suffix
    - maybe try im_start/end before
    - OR, <|file_sep|> instead?



### Context to send

- I suspect I can select context based on the code tree instead of just # lines before/after and might get better suggestsion that way when not sending entire file
    - i.e. pass entire scope of cursor location and stop at the "symbol" boundary...
    - include symbols too to complete other funcs
        - language specific? as to what to pass that is valid in a given language (IOTW only symbols visible within a given scope)
- recent edits (esp symbols, i.e. of a function edited in another file)

    - ************* TODO NEXT PRIORITY => I have plenty of context to provide a ton more of details... and quality will skyrocket... ******************

- clipboard contents (nice to have) and probably a waste of space? maybe some sort of detection if its code and if so then include it?
- It might be nice to allow the model to request additional context... i.e. not send clipboard all the time, just when it may be relevant
- let user indicate expand context (i.e. re-request but with bigger context -- like the next scope above, all of its code)
- File name
    - keep it in a comment in the prefix?
    - or, pass it in a separate file before FIM?
- pass repo (project name) token
- pass file name as a file separator token?
    - create some test code examples that are ambiguous without file name (similar languages) and see how it does w/ and w/o the name

### Prompting?

- Things to guide it:
    - No markdown if not a markdown file
    - Comments have to be valid (not just willy nilly text) =>  esp happens w/ new files that have maybe one comment at the top, it thinks its time to write a guide doc with text and code
- Comments work well (as is expected)

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
        - I probably want the instruct models
