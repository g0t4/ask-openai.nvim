*** StarCoder paper
  Qwen2.5Coder's Tech Report used this (at least for FIM)
  https://arxiv.org/pdf/2402.19173
  <repo_name>reponame<file_sep>filepath0\ncode0<file_sep><fim_prefix>filepath1\ncode1_pre<fim_suffix>code1_suf<fim_middle>code1_mid<file_sep> ...<|endoftext|>
     StarCoder2 doesn't include new line after reponame/filepathX, basically only between filepath\ncode...
     also means when no filepaths included then there are no new lines at all
     BUT, qwen examlpes show new lines:
       https://github.com/QwenLM/Qwen2.5-Coder/blob/main/examples/Qwen2.5-Coder-repolevel-fim.py
       AND, in my testing Qwen worked fine w/ and w/o newlines in several spots

  <file_sep>code1<file_sep>code2 ... <|endoftext|>
    50% of time repo metadata not included (no repo name, no file paths)..

  StarCoder2 paper also used these sentinels:
     see Table 5
       <issue_[start|comment|closed]>
       <pr>,<pr_[status|is_merged|base|file|base_code|diff|diff_hunk|comment|event_id|review|review_state|in_reply_to_review_id|in_reply_to_comment_id|diff_hunk_comment_line]>
       <jupyter_[start|text|code|output|script]>,<empty_output>
       <code_to_intermediate>, <intermediate_to_code>
    Q2.5C Tech Report mentions:  "In addition to raw code, we also collected data from Pull Requests, Commits, Jupyter Notebooks, and Kaggle datasets, all of which were subjected to similar rule-based cleaning techniques."

Comments note:
- Tech Report mentions: Since too many instruction samples without code snippets hurt the model performance on code generation tasks (e.g. MultiPL-E, McEval, and MdEval), we remove most of the samples without code snippets to keep the code generation capability of our instruction model.
- TLDR... stop putting dense comments into code... use a md file.
- And by dense I mean like 50 lines... a few is smart to keep local still

*** Repo-level + File-level FIM template:
-  official examples:
  -  https://github.com/QwenLM/Qwen2.5-Coder/blob/main/examples/Qwen2.5-Coder-repolevel.py
  -  https://github.com/QwenLM/Qwen2.5-Coder/blob/main/examples/Qwen2.5-Coder-repolevel-fim.py
- example is also in readme: https://github.com/QwenLM/Qwen2.5-coder?tab=readme-ov-file#4-repository-level-code-completion
- this is from the Qwen2.5-Coder Tech Paper: https://arxiv.org/pdf/2409.12186

    <|repo_name|>{repo_name}
    <|file_sep|>{file_path1}
    {file_content1}
    <|file_sep|>{file_path2}
    {file_content2}
    <|file_sep|>{file_path3}
    <|fim_prefix|>{code_pre}<|fim_suffix|>{code_suf}<|fim_middle|>{code_fim}<|endoftext|>

- FYI last file doesn't have to be FIM format, IIUC can complete the rest of the file if not fim tags (so you'd include all but end of the last file to geenrate the rest of it
- like not having a Sufix... so you only have Prefix and Middle... and I guess no need to include the FIM tokens?!
- for now I don't see value in using this format, using FIM tokens with empty Suffix s/b fine too

## Issues
- so far, repo+file-level FIM doesn't work well... 90% of predictions are "stop"/empty immediately
  - I observed this with llama.vim plugin too!
  - I definitely notice a diff b/w my file-level fim ONLY prompt (works very well) and this combo
      that said, when I developed my file-level FIM... even small mistakes led to problems / crap completions
      so lets make sure this is well understood and tested before I conclude anything
- I should do some testing in isolation to see how specific prompts behave before I coclude much about wheter or not repo+file level FIM is useful

## FIXED: Extraneous newline after file threw off indentation
- OMG... simple things can really throw off completions...
  - with repo level I had an extra \n at end of the FIM file (last file) and that messed up indentation when I put my cursor inside the function block in calc.lua! once I removed the extra trailing new line then the indentation worked again inside the function!
```
<|repo_name|>ask-openai.nvim
<|file_sep|>calc.lua
<|fim_prefix|>local M = {}

function M.add(a, b)
    <|fim_suffix|>
    return a + b
end



return M<|fim_middle|>
<-- this extra new line threw off indentation when cursor was inside function M.add above return! (press o to go into insert mode while on the return line... and bam the new line here was trouble... possibly b/c lua code may tend to end with no new lines? or I suppose MOST files end w/o extraneous new lines!! that might make more sense given typical unix line ending and EOF conventions
```


