## Predictions notes

- Obviously, short files do really well
    - Long files can be a challenge to get the right context

## TODOs

### Context to send

- I suspect I can select context based on the code tree instead of just # lines before/after and might get better suggestsion that way when not sending entire file
    - i.e. pass entire scope of cursor location and stop at the "symbol" boundary...
    - include symbols too to complete other funcs
        - language specific? as to what to pass that is valid in a given language (IOTW only symbols visible within a given scope)
- recent edits (esp symbols, i.e. of a function edited in another file)
- clipboard contents (nice to have) and probably a waste of space? maybe some sort of detection if its code and if so then include it?
- It might be nice to allow the model to request additional context... i.e. not send clipboard all the time, just when it may be relevant
- let user indicate expand context (i.e. re-request but with bigger context -- like the next scope above, all of its code)
- File name
    - keep it in a comment in the prefix?
    - or, pass it in a separate file before FIM?
- pass repo (project name) token
- pass file name as a file separator token?
    - create some test code examples that are ambiguous without file name (similar languages) and see how it does w/ and w/o the name

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



