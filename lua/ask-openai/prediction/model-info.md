Use ollama serve output when model is loaded to find these:
Or, repo: https://github.com/QwenLM/Qwen2.5-Coder

## qwen2.5-coder

- File level code completion:
    - https://github.com/QwenLM/Qwen2.5-Coder?tab=readme-ov-file#3-file-level-code-completion-fill-in-the-middle
    - Follow formatting guidelines in the model's paper:
        - https://arxiv.org/abs/2207.14255 (published 2022, must've been on earlier qwen-coder models, IIAC)
- Repo level (multiple files provided);
    - https://github.com/QwenLM/Qwen2.5-Coder?tab=readme-ov-file#4-repository-level-code-completion
    - TODO try this!!!


### File level:

prompt = '<|fim_prefix|>' + prefix_code + '<|fim_suffix|>' + suffix_code + '<|fim_middle|>'

example:

```sh
curl -X POST http://build21.lan:11434/api/generate \
    -d '{"raw":true,"num_predict":40,"model":"qwen2.5-coder:14b","stream":true,"prompt":"<|fim_prefix|>    <|fim_suffix|>    \n\n    it(\"some test\", function()\n        bounter = 100\n        assert.equals(\"bello Brian\", bello(\"Brian\"))\n    end)\n\n    it(\"some other test\", function()\n        assert.equals(0, bounter)\n    end)<|fim_middle|>"}'
```

BOS token        = 151643 '<|endoftext|>'
EOS token        = 151645 '<|im_end|>'
EOT token        = 151645 '<|im_end|>'
PAD token        = 151643 '<|endoftext|>'
LF token         = 148848 '├ä─¼'
FIM PRE token    = 151659 '<|fim_prefix|>'
FIM SUF token    = 151661 '<|fim_suffix|>'
FIM MID token    = 151660 '<|fim_middle|>'
FIM PAD token    = 151662 '<|fim_pad|>'
FIM REP token    = 151663 '<|repo_name|>'
FIM SEP token    = 151664 '<|file_sep|>'
EOG token        = 151643 '<|endoftext|>'
EOG token        = 151645 '<|im_end|>'
EOG token        = 151662 '<|fim_pad|>'
EOG token        = 151663 '<|repo_name|>'
EOG token        = 151664 '<|file_sep|>'
