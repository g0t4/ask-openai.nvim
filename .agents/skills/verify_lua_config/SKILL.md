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
     skills.lua
     skills.tests.lua
- `PlenaryBustedDirectory` has a retarded discovery convention: `*_spec.lua`... DO NOT USE THIS CRAP.

## Running a single test file

```sh
nvim --headless \
  -c "PlenaryBustedFile lua/ask-openai/frontends/skills.tests.lua" \
  -c "qa!"
```

## Run multiple test files

```sh
fd ".tests\.lua" | xargs -I_ nvim --headless -c "PlenaryBustedFile _" -c "qa!"
```

## Example for this repository

The repository ships with a suite of tests for the `ask-openai` plugin. To run
them all:

```sh
nvim --headless -c "PlenaryBustedDirectory lua/ask-openai" -c "qa!"
```

To run only the skill‑related tests:

```sh
nvim --headless -c "PlenaryBustedFile lua/ask-openai/frontends/skills.tests.lua" -c "qa!"
```

## Interpreting the output

The output follows the standard Plenary/Busted format, e.g.:

```
Scheduling: lua/ask-openai/frontends/skills.tests.lua
...
Success: 6
Failed : 0
Errors : 0
```

If the `Success` count matches the number of test cases, the configuration is
behaving as expected. Any failures will be listed with a detailed traceback.

## Automating in CI

Add the appropriate `nvim` command to your CI configuration (GitHub Actions,
GitLab CI, etc.). Ensure the CI runner has Neovim and Plenary installed, then
fail the job if the exit code is non‑zero (Plenary returns a non‑zero exit code
when tests fail).

## Using the skill

When an AI model needs to verify the Neovim configuration, it can inject the
following slash command into the prompt:

```
/verify_neovim_lua_config
```

The model can then include the guidance above or directly execute the command
in a shell.

--- End of skill ---
