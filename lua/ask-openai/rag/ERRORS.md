## IIUC when you edit a document before the indexer runs/completes... the content no longer matches

happens when rapidly editing a file, noted recently when editing end of file (IIRC it was when I was removing content at the end of the buffer/file)

```vim.messages.log
Error in decoration provider "line" (ns=nvim.treesitter.highlighter):
Error executing lua: .../neovim/0.11.4/share/nvim/runtime/lua/vim/treesitter.lua:195: Index out of bounds
stack traceback:
        [C]: in function 'nvim_buf_get_text'
        .../neovim/0.11.4/share/nvim/runtime/lua/vim/treesitter.lua:195: in function 'get_node_text'
        ...m/0.11.4/share/nvim/runtime/lua/vim/treesitter/query.lua:470: in function 'handler'
        ...m/0.11.4/share/nvim/runtime/lua/vim/treesitter/query.lua:884: in function '_match_predicates'
        ...m/0.11.4/share/nvim/runtime/lua/vim/treesitter/query.lua:1013: in function 'iter'
        ....4/share/nvim/runtime/lua/vim/treesitter/highlighter.lua:385: in function 'fn'
        ....4/share/nvim/runtime/lua/vim/treesitter/highlighter.lua:239: in function 'for_each_highlight_state'
        ....4/share/nvim/runtime/lua/vim/treesitter/highlighter.lua:358: in function 'on_line_impl'
        ....4/share/nvim/runtime/lua/vim/treesitter/highlighter.lua:457: in function <....4/share/nvim/runtime/lua/vim/treesitter/highlighter.lua:451>
```
