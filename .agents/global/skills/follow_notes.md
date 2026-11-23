---
description: pre-canned prompt to encourage following notes in the code file
models: gptoss
# gptoss is often lazy:
# - says it edited a file, but didn't...
#   - rare - show changes and claim the edit was done
#   - super rare - not even show the changes and just say it edited the file!
#   - in both cases prompting it to "apply" the changes is enough
# - will get what appears to be the minimal set of changes to comply with a subset of requirements
#   - GOAL: I want to circumvent this behavior in terms of only doing a subset of bullets / notes in the referenced file
---

Instead of typing up a lengthy prompt, I prefer to leave those notes in the relevant code file.
- Consider these notes part of your prompt.
- Also consider the significance of the location w.r.t. where you put the new code.

Treat each note as a TODO item that must be checked off before you are done.
- Please review each item after you think it is implemented

You are welcome to create multiple commits in the git repo as you finish each checklist item, or one large commit is fine too.
