## StarCoder2

Refer to paper for formatting specifics: https://arxiv.org/html/2402.19173v1#S5

### Format - Source Code (no FIM) w/ Repo/File Metadata

```
<repo_name>reponame<file_sep>filepath1\ncode1<file_sep>filepath2\ncode2 ... <|endoftext|>
```
- The only `\n` added is after `filepathX` and before the file's `codeX`
    - Obviously, the file's code can have `\n` too
- 50% of the time reponame/filepath was included, w/ the goal of making it optional during inference

### Format - Source Code (no FIM) w/o Metadata

```
<file_sep>code1<file_sep>code2 ... <|endoftext|>
```
- No added `\n`
- Only `\n` are from file contents (codeX)
- NO `<repo_name>reponame`
- NO `filepathX`

### FIM Format

```
<repo_name>reponame<file_sep>filepath0\ncode0<file_sep><fim_prefix>filepath1\ncode1_pre<fim_suffix>code1_suf<fim_middle>code1_mid<file_sep> ...<|endoftext|>
```

- The only `\n` added is after `filepathX` and before the file's `codeX`
- Obviously, the file's code can have `\n` too

### FIM notes

- FIM file can be in the middle of the files list?
- also sounds like you could do FIM on multiple files?! what?

- llm.nvim supports starcoder2
    - https://github.com/huggingface/llm.nvim
    - unfortunately llm.nvim doesn't support repo-level FIM:
        - no `file_sep` nor `repo_name`
        - https://github.com/search?q=repo%3Ahuggingface%2Fllm.nvim+file_sep&type=code
        - https://github.com/search?q=repo%3Ahuggingface%2Fllm.nvim+repo_name&type=code
    - I have my own fork of this by the way...
