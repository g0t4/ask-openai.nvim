POC to test how rag based context would help FIM (or even ask questions / rewrites)

## LSP server notes

```lu
vim.lsp.get_log_path()
```

```sh
tail -F ~/.local/state/nvim/lsp.log
```

### If we ever want external edits to refresh the index

The current behavior works well for my workflow. `ask_ls` loads the saved index at startup and queues file updates when I open or save a document. Two questions to revisit if stale results become noticeable:

- **While Neovim is running**, would it help to pick up edits from another editor, Codex, or a branch switch? Neovim can watch workspace globs and send `workspace/didChangeWatchedFiles`. Each changed URI could feed the existing per-file debounce and chunk dedupe. An external write raises a choice when that file also has unsaved buffer edits: which version should the index represent? For a disk-based update, checking the path when the queue drains would distinguish a deletion from an atomic save that replaced the file.
- **When Neovim starts**, how often has the working tree changed since the saved index was built? A watcher only sees events after registration. If those gaps matter, startup could compare files with the saved index and queue added, changed, or deleted paths. The cost of that check is worth weighing against how often a stale match actually gets in the way.
