---
description: Using `run_in_neovim` tool in the active Neovim process that hosts the agent harness.
---

# run_in_neovim tool

Examples:

- Call Neovim APIs (`vim.*`, `vim.api.*`, `vim.fn.*`).
- Read or modify buffers, windows, tabs, options, etc.
- Schedule timers.

The Neovim process executes the code and returns output and error messages.

Make sure commands won't harm user files and/or the machine.

## Examples

```lua
vim.notify('Hey WES, I asked you a question! Answer it, jerk!')
vim.notify("🧠 Agent has finished processing!")

local answer = vim.fn.input("Enter value: ")

-- help the user with diagnostic errors:
local diags = vim.lsp.diagnostic.get_all()

-- open a file you edited and run the code formatter on it
-- make sure to target the buffer by number (do not use current buffer because that's often chat buffer with your messages viewer)
-- assume CoC for Language Servers

-- execute vim(script) commands
vim.cmd(":echom 'hello'")

-- help user adjust options, then generate them into a script/config to apply on reload
vim.o.relativenumber = not vim.o.relativenumber

if pcall(require, "telescope.builtin") then
  require("telescope.builtin").find_files()
else
  vim.notify("Telescope is not installed", vim.log.levels.WARN)
end

local out = vim.fn.systemlist("git status --porcelain")

vim.defer_fn(function() vim.notify("Timer fired") end, 2000)

vim.api.nvim_open_win(bufnr, false, {relative='editor', width=80, height=20, row=5, col=5})

dofile(vim.fn.expand("~/.agents/instructs/run-lua/scripts/cleanup.lua"))
```
