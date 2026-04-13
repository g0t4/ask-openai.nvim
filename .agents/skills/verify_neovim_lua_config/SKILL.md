---
name: verify_neovim_lua_config
description: Guidance and command to run Plenary/Busted tests for Neovim Lua configuration
---

## Overview

This skill provides a concise, reproducible way to run **Plenary/Busted** style
tests for Neovim Lua configuration files. It is intended for use in headless
automation (e.g., CI pipelines) or by an AI agent that needs to verify that a
Neovim configuration works correctly.

## Prerequisites

1. **Neovim** – Ensure `nvim` is installed and reachable via the system `$PATH`.
2. **Plenary.nvim** – The plugin must be installed (e.g., via a plugin manager) so
   the `PlenaryBusted*` commands are available.
3. **Test files** – Your Lua test files should follow the Plenary/Busted
   conventions (`describe`, `it`, etc.) and be located under a directory such as
   `lua/your-plugin/tests` or `tests/`.

## Running a single test file

```sh
nvim --headless \
  -c "PlenaryBustedFile lua/ask-openai/frontends/skills.tests.lua" \
  -c "qa!"
```

* `PlenaryBustedFile <path>` runs the specified test file.
* `qa!` quits Neovim after the test run.

## Running all tests in a directory

```sh
nvim --headless \
  -c "PlenaryBustedDirectory lua/ask-openai/frontends" \
  -c "qa!"
```

Replace the directory path with the location of your tests. The command will
discover all `*_tests.lua` files (or any file that contains Plenary/Busted
syntax) and execute them.

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
