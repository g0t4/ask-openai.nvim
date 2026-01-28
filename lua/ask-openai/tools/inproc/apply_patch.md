## Use `apply_patch` to edit files.

Your patch language is a stripped‑down, file‑oriented diff format designed to be easy to parse and safe to apply. You can think of it as a high‑level envelope:

*** Begin Patch
[ one or more file sections ]
*** End Patch

Within that envelope, you get a sequence of file operations.
You MUST include a header to specify the action you are taking.
Each operation starts with one of three headers:

*** Add File: <path> - create a new file. Every following line is a + line (the initial contents).
*** Delete File: <path> - remove an existing file. Nothing follows.
*** Update File: <path> - patch an existing file in place (optionally with a rename).

If you want to rename the file too, immediately follow with:
*** Move to: <new path>

Then one or more “hunks”, each introduced by @@ (optionally followed by a hunk header).
Within a hunk each line starts with:

- for inserted text,
* for removed text, or
  space ( ) for context.
  At the end of a truncated hunk you can emit *** End of File.

Here is the grammar:

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

A full patch can combine several operations:

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

It is important to remember:

- You must include a header with your intended action (Add/Delete/Update)
- You must prefix new lines with `+` even when creating a new file

Tips on a failure:
- You only need enough context for a unique match!
- The line(s) you replace are context too; if they’re unique, no additional context is needed.
- Split bigger patches into smaller patches, i.e. if editing two functions, try each separately!
- Watch out for whitespace differences, i.e. blank lines

Please be curteous:
- NEVER leave comments about removed code, just get rid of it. This code lives in a git repo.
- Check your work! Especially after a failure.

