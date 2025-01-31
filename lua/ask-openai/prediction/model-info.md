Use ollama serve output when model is loaded to find these:
Or, repo: https://github.com/QwenLM/Qwen2.5-Coder

## deepseek-r1

```log
llm_load_print_meta: general.name     = DeepSeek R1 Distill Qwen 14B
llm_load_print_meta: BOS token        = 151646 '<｜begin▁of▁sentence｜>'
llm_load_print_meta: EOS token        = 151643 '<｜end▁of▁sentence｜>'
llm_load_print_meta: EOT token        = 151643 '<｜end▁of▁sentence｜>'
llm_load_print_meta: PAD token        = 151643 '<｜end▁of▁sentence｜>'
llm_load_print_meta: LF token         = 148848 'ÄĬ'
llm_load_print_meta: FIM PRE token    = 151659 '<|fim_prefix|>'
llm_load_print_meta: FIM SUF token    = 151661 '<|fim_suffix|>'
llm_load_print_meta: FIM MID token    = 151660 '<|fim_middle|>'
llm_load_print_meta: FIM PAD token    = 151662 '<|fim_pad|>'
llm_load_print_meta: FIM REP token    = 151663 '<|repo_name|>'
llm_load_print_meta: FIM SEP token    = 151664 '<|file_sep|>'
llm_load_print_meta: EOG token        = 151643 '<｜end▁of▁sentence｜>'
llm_load_print_meta: EOG token        = 151662 '<|fim_pad|>'
llm_load_print_meta: EOG token        = 151663 '<|repo_name|>'
llm_load_print_meta: EOG token        = 151664 '<|file_sep|>'
```

## qwen2.5-coder

- File level code completion:
    - https://github.com/QwenLM/Qwen2.5-Coder?tab=readme-ov-file#3-file-level-code-completion-fill-in-the-middle
- Repo level (multiple files provided);
    - https://github.com/QwenLM/Qwen2.5-Coder?tab=readme-ov-file#4-repository-level-code-completion
    - TODO try this!!!

### Research paper notes - https://arxiv.org/abs/2207.14255 (published 2022)

- Suggested to read this paper and follow its guidance on formatting for FIM inference
- Observations/questions for me to consider
    - is it useful to include any sort of "instruction message" along with the FIM request...
        - where would that go in the raw prompt? AFAICT they are not training with that so there may not be a way to do that... and have it have any impact on the suggestion.. IOTW use PREFIX/SUFFIX for all guidance...
            - WAIT, what if I add comment lines at the top of the prefix to explain the type of file?
            - If those appear in the wild, that might help (i.e. SHEBANG?)
        - Should I just assume it will handle inferring the language from the prefix/suffix? (i.e. python vs lua vs cpp, etc) seems ok so far
        - If I ask for completion with small prefix/suffix, yeah that's gonna struggle but otherwise the language is likely obvious (i.e. from imports/requires/syntax peculiarities)
        - Paper does mention `"Steerable generation"` that sounds like what I am thinking about here...
    - Adapt to document-level vs context-level FIM...
        - i.e. if entire documents tend to be FIM'd then wouldn't it make most sense to feed in entire current document for FIM?
        - or if batches of subdocs were grouped then what does that mean?
        - does this have any impact on how much context I give the model (prefix/suffix?)
    - When I generate code completions, I personally don't think connecting the end of the generated text to the start of the suffix is a big deal...
        - So, ensuring <EOT> in generation is less important, I SUSPECT
        - BASICALLY, I like to accept partial generations,
            - which should connect well with the end of the Prefix...
        - I see this as a series of completions so I can push the model in the right direction along the way...
            - a COT for completions if you will, I get to sprinkle in new, critical context along the way
            - I also get to cut off suggestions I don't want before they are a mile long
    - FIM + SUFFIX mods? ... could you train a model to allow it to generate not only the middle but the suffix and allow the suffix to be altered?
        then use a diff tool to figure out changes to the document that are suggested by both FIM and SUFFIX diff mods
        - IIAC this might be how zed's model generates suggestions to existing code not just new middle section code... also supermaven does this... what would that look like?
- Middle span selection
    - Best overall performance seems to be random split on character level, though line-level can lead to slight improvements in single/multi-line infill tests (almost negligible though)
    - SO, IIUC... this means I don't need to fret about where to split prefix/suffix (i.e. not on line boundary, but can do whatever char the cursor is on, IIAC)
- PSM chosen for format (<PRE>prefix<SUF>suffix<MID>)
    - also tested SPM format
        - IIUC they train with 50/50 PSM/SPM.. and I can use both IIUC?
        - SPM mostly chosen to avoid invalidating cache of key/values... b/c assume that changes to suffix are less likely than prefix?
        - also says SPM had slight edge over PSM for infilling benchmarks?
- Detect if model generated <EOT> token?
    - Model should generate <EOT> to endicate that it connected prefix and suffix, otherwise if no EOT in a reasonable token budget size... then that indicates the generated text is likely incomplete and/or of lower quality...
    - can I add detection of this to the client?
    - would this be done_reason/stop_reason? Does "stop" mean it received EOT? vs what else?
    - Try limit predicted tokens to small amount and see if it fails to produce stop reason?
- Prepend <EOT>? paper suggests this boosts perf
    - TODO TRY PSM inference => <EOT><PRE>prefix...
- Context-level vs Document-level FIM
    - \*\*\* IIUC this affects training alone, no impact on inference AFAICT
    - IIUC in training documents are "glued" together with <EOT> tokens
        - then a subset are taken that fit within the model context limit (say 128k tokens)
    - A subset of docs are selected for FIM transform (PSM/SPM 50/50)
    - FIM transform can happen:
        - Before chunking for model conext limit
        - After chunking for model context limit
    - If before (aka Document level FIM):
        - Long documents (IIUC past context limit) can become fragmented and lose prefix (part of it goes into one training run, rest goes into next
        - To avoid this, they can use FIM transform AFTER chunking for model context limit
    - If after (aka Context level FIM):
        - Take chunk and FIM transform applicable documents
        - Make sure result still fits in model context limit (IIUC FIM tokens may push over the limit)

### File level:

prompt = '<|fim_prefix|>' + prefix_code + '<|fim_suffix|>' + suffix_code + '<|fim_middle|>'

example:

```sh
curl -X POST http://ollama:11434/api/generate \
    -d '{"raw":true,"num_predict":40,"model":"qwen2.5-coder:14b","stream":true,"prompt":"<|fim_prefix|>    <|fim_suffix|>    \n\n    it(\"some test\", function()\n        bounter = 100\n        assert.equals(\"bello Brian\", bello(\"Brian\"))\n    end)\n\n    it(\"some other test\", function()\n        assert.equals(0, bounter)\n    end)<|fim_middle|>"}'
```

BOS token = 151643 '<|endoftext|>'
EOS token = 151645 '<|im_end|>'
EOT token = 151645 '<|im_end|>'
PAD token = 151643 '<|endoftext|>'
LF token = 148848 '├ä─¼'
FIM PRE token = 151659 '<|fim_prefix|>'
FIM SUF token = 151661 '<|fim_suffix|>'
FIM MID token = 151660 '<|fim_middle|>'
FIM PAD token = 151662 '<|fim_pad|>'
FIM REP token = 151663 '<|repo_name|>'
FIM SEP token = 151664 '<|file_sep|>'
EOG token = 151643 '<|endoftext|>'
EOG token = 151645 '<|im_end|>'
EOG token = 151662 '<|fim_pad|>'
EOG token = 151663 '<|repo_name|>'
EOG token = 151664 '<|file_sep|>'
