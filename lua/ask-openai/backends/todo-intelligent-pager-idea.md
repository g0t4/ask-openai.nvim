What if I write a new pager (i.e. less) that:
- can detect syntax per line and highlight it automatically
- push a button to pretty print current line (and another to collapse it down)
   - conversely, a button to compact a line (even more so than originally)
- when it detects a stack trace, immediately pass it off to an LLM and show the response somehow codelens style so by the time I find the stack trace there is additoinal context available
    think of this as more helpful error messages without needing the maintainer of the software to implement it
- AI codelen - intelligent selection on current line to drill in if you will... i.e. use treesitter to then take the current node and remove everyhing above it (to zoom in)
   - AI can comment on any part of the output!
- works well with fzf style fuzzy search
- diff vs past runs!
   - think profiling and taking a memory snapshot
   - could even have a key to take explicit snapshots AND name them


naturally:
- tail any file
- wide color compat


