---
name: run-lua
description: |
  Enables agents to run arbitrary Lua code in the active Neovim process via the
  `run_lua` OpenAI tool.  Includes practical examples (e.g. `vim.notify`) and a
  catalog of useful Neovim actions an agent can perform once it has code‑execution
  capabilities.
license: MIT
compatibility: |
  Neovim ≥ 0.9 with built‑in LuaJIT.  Requires the `run_lua` tool to be enabled
  in the agent runtime.  No external network access is required.
allowed-tools: run_lua
---

# Run‑Lua Skill

## Overview
The `run_lua` tool lets an agent send a string of Lua code that will be executed
inside the same Neovim instance that hosts the agent.  Because the code runs in
the editor process it can:

* Call any Neovim API (`vim.*`, `vim.api.*`, `vim.fn.*`).
* Interact with installed plugins.
* Read or modify buffers, windows, tabs, and global options.
* Schedule timers or create autocommands.
* Execute external commands via `vim.fn.system`.

> **Security note** – The tool runs **untrusted** code.  Agents should only use
> this skill when they have explicit permission, and the surrounding
> infrastructure should sandbox or audit the code when possible.

## Enabling the Tool
The agent runtime must expose the `run_lua` tool (see
`lua/ask-openai/tools/inproc/run_lua.lua`).  When the skill is activated, the
agent sends a request like:

```json
{
  "tool": "run_lua",
  "code": "vim.notify('Hello from the agent!')"
}
```

The Neovim process executes the code and returns any output or error message.

## Example 1 – Send a User Notification

```lua
---@param msg string
local function notify_user(msg)
  -- Show an informational toast in the UI
  vim.notify(msg, vim.log.levels.INFO)
end

notify_user("🧠 Agent has finished processing!")
```

*Result:* A popup appears in Neovim with the supplied message.

## Example 2 – Append a Line to the Current Buffer

```lua
---@param line string
local function append_line_to_current_buffer(line)
  local bufnr = vim.api.nvim_get_current_buf()
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  -- Insert the new line at the end of the buffer
  vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, { line })
end

append_line_to_current_buffer("-- Added by the run_lua skill")
```

*Result:* The text `-- Added by the run_lua skill` appears at the end of the file.

## Example 3 – Execute a Normal‑mode Command

```lua
-- Save the current buffer without prompting
vim.cmd("write")
```

*Result:* The buffer is written to disk.

## Example 4 – Toggle an Option

```lua
-- Flip the `relativenumber` setting
vim.o.relativenumber = not vim.o.relativenumber
```

*Result:* Line numbers switch between absolute and relative.

## Example 5 – Interact with a Plugin (e.g. Telescope)

```lua
-- Open Telescope file finder if the plugin is available
if pcall(require, "telescope.builtin") then
  require("telescope.builtin").find_files()
else
  vim.notify("Telescope is not installed", vim.log.levels.WARN)
end
```

*Result:* Telescope’s file picker launches if the plugin is installed.

## Additional Capabilities an Agent Can Leverage

| Capability | Sample Code Snippet | Use Case |
|------------|---------------------|----------|
| **Create a floating window** | `vim.api.nvim_open_win(bufnr, false, {relative='editor', width=80, height=20, row=5, col=5})` | Show temporary UI, render markdown, or prompt the user. |
| **Read user input** | `local answer = vim.fn.input("Enter value: ")` | Collect parameters for later steps. |
| **Run an external command** | `local out = vim.fn.systemlist("git status --porcelain")` | Query VCS state, show diffs, or decide on further actions. |
| **Schedule a timer** | `vim.defer_fn(function() vim.notify("Timer fired") end, 2000)` | Delay notifications or perform periodic checks. |
| **Define an autocommand** | `vim.api.nvim_create_autocmd("BufWritePost", {pattern="*.lua", callback=function() vim.notify("Lua file saved") end})` | React to file events automatically. |
| **Query LSP diagnostics** | `local diags = vim.lsp.diagnostic.get_all()` | Summarize errors/warnings across the workspace. |
| **Manipulate tabs/windows** | `vim.api.nvim_set_current_tabpage(vim.api.nvim_tabpage_list()[2])` | Switch context based on task requirements. |
| **Load and execute a script from the skill package** | `dofile(vim.fn.expand("~/.agents/skills/run-lua/scripts/cleanup.lua"))` | Keep complex logic in separate files for readability. |

## How to Extend This Skill
If you need more sophisticated behavior, add Lua scripts under a `scripts/`
folder inside the skill directory and reference them from the examples above.
For instance, a reusable cleanup helper could live in
`scripts/cleanup.lua` and be invoked with:

```lua
dofile("scripts/cleanup.lua")
```

---

*Skill authored for the **Ask‑OpenAI.nvim** plugin, version 1.0.0.*

