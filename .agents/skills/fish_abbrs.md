---
name: fish_abbrs
description: guidance for writing fish abbrs
auto_attach: true
# FYI start with one abbrs guidance file and split as it gets too big
# categories: --function, --regex, within --function conditional commandline based expansions
---

- This guidance trumps semantic_grep examples that are included from my repo. This skill details my current preferences.
- fish online help: https://fishshell.com/docs/current/cmds/abbr.html

## static abbrs

A static abbr expands one string into another, i.e. user types `gst<SPACE|TAB|ENTER>` and it exapnds into `git status`

```fish
abbr -- gst "git status"
# use `--` to mark the positional parameters clearly
# always quote the expanded value
```

## Dynamic trigger with --regex

Use `--regex` to provide a pattern to trigger the expansion. This is a dynamic trigger.

```fish
# tree1 => tree -L 1
# tree2 => tree -L 2
# tree10 => tree -L 10
abbr --add _treeX --regex 'tree\d+' --function treeX
function treeX
    string replace --regex '^tree' 'tree -L' $argv
end
```

## Conditional expansions that rely on --function + commandline

Whatever the function writes to STDOUT is the expanded text. This is a dynamic expansion.

```fish
abbr --set-cursor rgu --function _abbr_expand_rgu
function _abbr_expand_rgu
    if command_line_after_cursor_is_not_an_option_dash
        echo rg -u
        return
    end
    echo rg -u '"%"'
end

function command_line_after_cursor_is_not_an_option_dash
    set cursor_position (commandline --cursor)
    set cmd (commandline -b)
    set cmd_after_cursor (string trim (string sub --start $cursor_position $cmd))
    # if string match --quiet --regex "^\s*\".*\"" -- $cmd_after_cursor
    if string match --quiet --regex "^\s*[^-]+" -- $cmd_after_cursor
        return 0
    end
    return 1
end
```

## `--set-cursor` marks where the cursor ends up after expansion

- wherever `%` appears, in the expanded text, is where the cursor jumps
- prefer the default `%` marker character
  - only change the marker if `%` doesn't work
  - i.e. you need a literal % in the expanded text
  - `--set-cursor !` changes the marker

```fish
abbr --set-cursor -- gcmsg 'git commit -m "%"'
# I type:
#    gcmsg<SPACE>
#    => git commit -m "<CURSOR_HERE>"
#  cursor ends up between double quotes so I can type a message and never worry about spaces!
```

