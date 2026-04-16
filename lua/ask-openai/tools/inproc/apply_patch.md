## Use `apply_patch` to edit files.

Your patch language is a stripped‑down, file‑oriented diff format designed to be easy to parse and safe to apply.

*** Begin Patch
[ one or more file operations ]
*** End Patch

Each “operation” MUST start with one of three “headers”:

*** Add File: <path> - every following line is a + line (the initial contents).
*** Delete File: <path> - remove an existing file. Nothing follows.
*** Update File: <path> - in-place edits (optionally with a rename).

UpdateFile can be immediately followed by MoveTo to rename the file:
*** Move to: <new_path>

Then one or more “hunks”, each introduced by @@ (optionally followed by a hunk header).

Within a hunk each line starts with:
+ for inserted text,
- for removed text, or
  space (" ") for context (unchanged lines to match)

At the end of a truncated hunk you can emit:
*** End of File

### Here is the grammar:

Patch := Begin { FileOp } End
Begin := "*** Begin Patch" NEWLINE
End := "*** End Patch" NEWLINE
FileOp := AddFile | DeleteFile | UpdateFile
AddFile := "*** Add File: " path NEWLINE { "+" line NEWLINE }
DeleteFile := "*** Delete File: " path NEWLINE
UpdateFile := "*** Update File: " path NEWLINE [ MoveTo ] { Hunk }
MoveTo := "*** Move to: " newPath NEWLINE
Hunk := "@@" [ header ] NEWLINE { HunkLine } [ "*** End of File" NEWLINE ]
HunkLine := (" " | "-" | "+") text NEWLINE

### A full patch can combine several operations:

*** Begin Patch
*** Add File: hello.txt
+Hello world
*** Update File: src/app.py
*** Move to: src/main.py
@@ def greet():
-print("Hi")
+print("Hello, world!")
*** Delete File: obsolete.txt
*** End Patch

### Reminders

- Verify your changes with `git diff foo.json`
- Nothing wrong with commands too:
  - `rm foo.json` to delete
  - `mv foo.json bar.json` to rename
  - `rename` for bulk rename
- Don't be that guy that uses DeleteFile followed by AddFile just to rename a file!
