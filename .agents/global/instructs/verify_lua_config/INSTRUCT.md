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
```
