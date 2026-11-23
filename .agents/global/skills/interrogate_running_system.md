---
description: diagnose problems by interrogating the live/running system, not just reading static config files
---

# Interrogate the Running System

When diagnosing a problem, **don't guess** from static config files alone. Config files only show *intent*; the running system shows *truth*. Interrogate the live system to see what's **actually** registered, configured, and happening.

## Why

Static files can lie or be misleading:
- A plugin may be listed in config but not actually loaded.
- A default may be overridden at runtime by another plugin.
- Autocmds may be registered conditionally or by a dependency you didn't expect.
- Config files may have changed since the running process started.

Interrogating the live system reveals what's **really** going on.

## How (general principle)

Find the tool that lets you inspect the running system, then ask it targeted questions:

| System | Introspection mechanism |
|---|---|
| Neovim | `run_in_neovim` (Lua in the live process) |
| Running process | `ps`, `lsof`, signals, debugger attach |
| HTTP service | health endpoints, live logs, `curl` against it |
| Database | live queries, `EXPLAIN`, `\d` schema |
| Shell | `type`, `which`, `alias`, `set`, env vars |

Then ask questions like:
- "What handlers are **actually** registered for event X?"
- "What is the **effective** value of setting Y right now?"
- "What is **loaded/enabled** at runtime?"
- "What happened on the last trigger of event Z?"

## Example: Neovim cursor flicker (real trace)

Problem: cursor flickers down to the command line while typing in insert mode.

**Static analysis** (reading configs) gave many candidate suspects:
- `ask-openai.nvim` predictions (extmark/virt_text redraws)
- `illuminate.nvim` (full-buffer scans)
- `lualine` statusline components
- `showmode` showing `-- INSERT --`

Too many hypotheses — no way to know which was real.

**Live introspection** via `run_in_neovim` settled it with direct evidence:

```lua
-- Which autocmds fire on every keystroke in insert mode?
local autocmds = vim.api.nvim_get_autocmds({ event = "CursorMovedI" })
-- -> found lualine_stl_refresh + lualine_tal_refresh
--    (lualine refreshes statusline AND tabline on EVERY CursorMovedI)

-- What's the effective refresh config?
vim.inspect(require("lualine").get_config().options.refresh)
-- -> events include "CursorMovedI"  <-- the smoking gun

-- What's the effective setting right now?
vim.o.showmode  -- -> true  (shows "-- INSERT --" in command line)
```

The live query revealed that lualine was refreshing on **every keystroke** (via `CursorMovedI`), and `showmode` was showing `-- INSERT --` in the command line directly above the statusline. That was the actual root cause — not the plugins that static analysis had suspected.

The fix followed directly from the evidence: remove `CursorMovedI` from lualine's refresh events and disable `showmode`.

## Safety note

Prefer **read-only introspection** (querying state). If the tool can also modify the system (e.g. `run_in_neovim` can run arbitrary Lua), use it to **inspect**, not to **edit**. Make edits through the normal, reviewable path (e.g. `apply_patch` + `git diff`), so changes are auditable.
