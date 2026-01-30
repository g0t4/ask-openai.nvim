## Commands

Here are noteworthy commands you have access to:

- fd, rg, gsed, gawk, jq, yq, httpie
- exa, icdiff, ffmpeg, imagemagick, fzf

Here are some *suggestions* too...

### Use `fd` to list files

```sh
# Usage: fd [OPTIONS] [regex] [path]...
fd                      # list files and dirs (except hidden and ignored)
fd foo                  # basename contains "foo" (regex)
fd '^foo' src           # limit to "src" directory (path)
fd --extension js
fd -p foo               # --full-path contains foo
fd --type file
fd --type dir

fd -l                   # think: ls -l
fd --exec stat          # execute stat on each result

fd --hidden             # show hidden files == start with dot like .bashrc
fd --no-ignore          # disable using .gitignore, .ignore, .fdignore to hide files
fd --unrestricted    # show everything: both hidden and ignored

fd --exclude node_modules # glob exclusion (not regex)

fd --max-depth 3
fd --size +10M
fd --changed-within 2hours
fd --changed-before 7days

# Files are versioned in git, so you can use `git` to find files too:
git ls-files

# other commands are fine too! as long as they're not needlessly slow / verbose!
```

### Use `rg` (ripgrep) to search file contents

```sh
rg bar # instead of grep -R
rg -o bar  # only matched part (grep -o)
rg -v bar # invert match (grep -v)
rg --glob="*manual*" embed  # glob filters paths (contains manual)
rg --glob="!*manual*" embed  # ! excludes (does not contain manual)
rg --max-depth 1
rg --multiline

# list files only:
rg --files-with-matches # or -l
rg --files  # list searched files

fd | rg foo # search STDIN
```

### _Verboten_ Commands

> [!WARNING]
> NEVER use `ls -R`
> NEVER use `grep -R`
> NEVER use `find . -type f`

Why? Because they are _SLOW_ and generate tons of useless output as they hoover up `node_modules`, `.venv`, etc because they don't support `.gitignore` exclusions.

Other costly mistakes to avoid:
```sh
ls -R ~ # gonna be a late night 🥱
ls -R / # only assholes do this 😈
```

