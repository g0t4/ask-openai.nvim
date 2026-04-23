---
description: |
    Tell LLM to remove its comments.
    Run this after a series of changes.

# PRN? remove comments guidance from most of my instructions/prompts and just use this after the fact?
# I do wonder if comments serve as additional, interleaved reasoning? And, if that is part of why gptoss120b ignores my pleas not to comment?
---

Please remove all comments you added in prior steps (i.e. file changes in apply_patch tool calls)

DO NOT remove comments you didn't add
