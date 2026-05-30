---
name: squash_last_commit
description: squash last commit onto previous when changes are related
---

Use this instruct when the user says `/squash` or when the last commit and the one before it are clearly related (e.g., a bugfix for a feature just added, or an iterative improvement to the same code).

## Squash Command

When invoked, execute:

```sh
git reset --soft HEAD~1 && git commit --amend -C HEAD~1
```

This:
1. `reset --soft HEAD~1` — unstages the last commit but keeps changes in the working tree
2. `commit --amend -C HEAD~1` — amends the previous commit, reusing its message

## When to use

- The user types `/squash`
- You notice two consecutive commits that modify the same file(s) and are logically related
- The user says "squash these" or "combine these commits"

## When NOT to use

- Commits are semantically distinct (e.g., refactoring + new feature)
- The user explicitly wants separate commit history
- There are uncommitted changes that shouldn't be included
