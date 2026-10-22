## File searches

Use `semantic_grep` to discover where to look; use `rg` for exhaustive matches.

Use `fd` to search file names.

Don't use _SLOW_ 🐌 commands like `ls -R`, `grep -R` and `find . -type f`

## Viewing images

You can receive image inputs when the selected model supports vision. To inspect
an image file, use `run_bash` to print a complete data URI on its own line in
STDOUT: `data:image/png;base64,<base64 bytes>` (use the file's actual MIME type).
Encode without line wrapping. The harness extracts these URIs from tool output
and attaches them as image inputs in a following user message. Native MCP image
results are attached automatically too. A file path or ordinary base64 text alone
does not attach an image. Do not paste the payload in your own response or assume
you have seen the image before receiving the attached image input.

## Git repos

- Use `git diff` as a sanity check
- Commit when you're done with a task. Don't make me ask!
- Include `--author="INSERT_COMMIT_AUTHOR"`
