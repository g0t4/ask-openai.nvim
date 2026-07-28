# Refactoring: Replace Hardcoded Values with Constants

## Goal

Remove magic strings and other hardcoded values (model names, config keys, etc.) and replace them with centralized constants to improve maintainability and reduce duplication.

**Furthermore, constants help with code discoverability because they express a relationship between consumers.**

## Process

Below includes a lua example. This process applies the same for most languages.

### Identify existing constants

- Find existing constants. Especially if mentioned by the user in the request.
    - Usually these are multiple uppercase letters, i.e.:
      `rg "[A-Z_]{2,}\b.*=" --type lua`
- Or, find a spot that seems appropriate to add them.
    - Use language appropriate casing which is often UPPERCASE, i.e.:
    - Follow language guidance for naming, prefer clarity

```lua
M.GPTOSS = "gptoss"
M.QWEN = "qwen"
M.GEMMA4 = "gemma4"
M.GLM = "glm"

M.DEFAULT_MODEL = gptoss

M.MAX_VALUE = 100
M.MIN_VALUE = 1

```

### Find All Usages

```bash
rg "\"(gptoss|gemma4|qwen|glm)\"" --type lua -n
```

Do not blindly find and replace, review each match on its own merits. For example if a word is used in an error message, ask yourself if it really needs to be made dynamic in that case, chances are the error message can be left as-is for readability of the error logic.

### Apply Replacements

For each consumer:

1. Check if there's already an import. If not, prefer adding one at the top of the file unless there's a conflict.
   `local models = require("ask-openai.config.models")`
2. Update usages, i.e.:
   `model == "gptoss"` → `model == models.GPTOSS`

### Verify

It's always wise to double check with git diff before or after committing. Check each change and make sure it feels right.

And, use typical verification steps such as:

```bash
# syntax check and/or compile changed files
luac -p file1.lua file2.lua ...

# search all again
rg '== "(gptoss|gemma4|qwen|glm)"' --type lua

# Review diff before commit
git diff
```
