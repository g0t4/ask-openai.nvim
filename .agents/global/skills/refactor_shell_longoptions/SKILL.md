---
name: longoptions
description: Expands short command‑line options in shell scripts to their long‑form equivalents.
---

You are given a shell script. Rewrite it so that every command‑line short option usage, that has a long‑form equivalent, is replaced with its long option.

Assume it is a _FISH_ shell script if not otherwise specified.

Pay attention to the shell type as some shell commands/builtins differ across shell bash/zsh/fish/etc. Also pay attention to platform differences, i.e. GNU vs BSD (see examples below).

- NEVER add comments to explain your changes.
- If a short option has no documented long counterpart, leave it as‑is.
- ONLY replace short options with long options, do not change ANYTHING else.

## (optional) Lookup help

If you feel uncertain about options:
- Run the command with `--help`
- Or, `fetch` online help:
    - https://fishshell.com/docs/current/cmds/complete.html
    - https://manpages.org/ls

Never run --help if doing so would modify the system.

Examples:
```sh
rg --help
fd -h

# reminder: subcommands often have extra options, in addition to global options
docker compose --help
docker --help

git clone -h
git -h

# some commands have options to expand help
ffmpeg -h   # short help
ffmpeg -h full  # detailed help

# use man page if command doesn't show useful help output
# just make sure to run man in a non-blocking fashion (i.e. no pager)
PAGER=none man ls
```

## Example replacements

Here are example replacements:
```fish
rg -g # BEFORE
rg --glob # AFTER

rg -L # BEFORE
ripgrep --follow # AFTER
```

## Caveats (GNU vs BSD)

When a short option maps to a GNU‑only long form (or vice‑versa), **do not** replace it unless the script makes clear it is only for one platform.

Below are the most common GNU/BSD divergences you should watch for while expanding short options:
- **`ls`**
  - GNU `ls` supports `--author`, `--group-directories-first`, `--color`, etc.
  - BSD `ls` (including macOS) does **not** have these flags; it uses `-G` for colour and lacks `--author`.
- **`grep`**
  - GNU `grep` offers `--binary-files`, `--color`, `--exclude`, `--include`, etc.
  - BSD `grep` does not support many of those long forms (e.g. `--color` is `-G`).
- **`sed`**
  - GNU `sed` supports `--regexp-extended`, `--quiet`, `--in-place`, etc.
  - BSD `sed` (including macOS) has slightly different flag semantics (`-E` for extended regex, `-n` for quiet, `-i ''` for in‑place)

## Allowed short options

The following short options are allowed, do not change these to long options:

```sh
ls -a -l
grep -i
rg -i
sed -n
```

But, _NEVER_ change long options to short options.
