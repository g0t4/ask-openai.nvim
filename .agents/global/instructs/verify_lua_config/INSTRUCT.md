---
name: verify_lua_config
description: how to verify lua modules for neovim and hammerspoon
---

I use **Plenary/Busted** style tests for Neovim and Hammerspoon configuration files (scripts).

## Prerequisites

1. **plenary.nvim** plugin
    - check with
      `:= vim.iter(vim.fn.getscriptinfo()):filter(function(s) return s.name:match("plenary.nvim") end):totable()`
    - provides `PlenaryBusted*` commands

## Naming

- Test file names end with `.tests.lua`
- Put new test files next to the system under test. Name accordingly:
     module.lua
     module.tests.lua
- `PlenaryBustedDirectory` has a retarded discovery convention: `*_spec.lua`... DO NOT USE THIS CRAP.

## Running a single test file

```sh
nvim --headless \
  -c "PlenaryBustedFile lua/ask-openai/frontends/instructs.tests.lua" \
  -c "qa!"
```

## Run multiple test files

```sh
fd ".tests\.lua" | xargs -I_ nvim --headless -c "PlenaryBustedFile _" -c "qa!"

## Polling with `vim.wait`

When a test needs to wait for an asynchronous condition (e.g., a server becoming
available, a file being written, or a variable being set), you can use Neovim's
built‑in `vim.wait` helper. It repeatedly calls a predicate until it returns a
truthy value **or** a timeout expires. The function signature is:

```lua
vim.wait(timeout_ms, condition, interval_ms?)
```

* `timeout_ms` – total time to wait in milliseconds.
* `condition` – a function that should return `true` when the desired state is
  reached.
* `interval_ms` – optional polling interval (default 200 ms). Use a smaller
  interval (e.g., `50`) for faster feedback in tests.

The call returns `true` if the condition succeeded, otherwise `false` when the
timeout is hit. This makes it perfect for writing **failing** tests that assert
the condition eventually becomes true, for example:

```lua
local ok = vim.wait(2000, function()
    return my_module.is_ready()
end, 50) -- poll every 50 ms for up to 2 seconds
assert.is_true(ok) -- test fails if the module never becomes ready
```

Use this pattern instead of manual timers or callbacks to keep tests simple and
deterministic.
```
