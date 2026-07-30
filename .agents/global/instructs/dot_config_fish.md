---
description: project specific fish config stored in `.config.fish`
auto_attach: true
---

## .config.fish

Think of this as project specific fish configuration (scripts).
- When I `cd` into a directory containing a `.config.fish`, it is automatically sourced by fish.
- Alternatively, it looks for the first parent directory that has a `.config.fish`
- Typically I put these in a repo's root directory.
- Ocassionally I put them in a nested repo directory for a subsystem.
- When you `cd` out, it is cleaned up (erases abbrs, functions, etc.).

Use this for project-specific abbrs/functions/etc that shouldn't clutter your global shell. For example:
- run_build
- run_tests
- run_tests_for_only_foo
- run_tests_for_only_bar

**Source Code:** [auto-dir-fish-config.fish](~/repos/github/g0t4/dotfiles/fish/load_last_interactive_only/auto-dir-fish-config.fish)
