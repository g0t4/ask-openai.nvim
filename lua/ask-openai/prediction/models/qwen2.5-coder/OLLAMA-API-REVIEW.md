## review of ollama APIs, and indirectly llama-server as well

Endpoints of note:
- `/api/generate`  (ollama specific endpoint)
    - hereafter referred as `generate`
- `/v1/completions`  (aka legacy openai completions)
    - hereafter referred to as `legacy`

Behind the scenes ollama spins up a `llama-server` instance per model, when requested


## Entrypoints

- Route registrations
   https://github.com/ollama/ollama/blob/main/server/routes.go#L1146

- [GenerateHandler](https://github.com/ollama/ollama/blob/main/server/routes.go#L111)
    - Both endpoints use `GenerateHandler`

        - calls `scheduleRunner` to start a runner (if not already)

           uses [`GetModel`](https://github.com/ollama/ollama/blob/main/server/images.go#L230) to lookup model info (i.e. template, options)
              wow ollama is using a docker manifest for models...
                  "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
                  cat ~/.ollama/models/manifests/registry.ollama.ai/library/qwen2.5-coder/7b | jq
                      manifest is tied to each tag, just like docker images, cool!
                      OCI Artifact Spec IIAC is what this is technically using?
                  and a `config`, i.e. 7b's:
                      cat "/Users/wesdemos/.ollama/models/blobs/sha256-d9bb33f2786931fea42f50936a2424818aa2f14500638af2f01861eb2c8fb446" | jq
                      not very much in here, just some metadata that is useful to know which model it is (not the params AFAICT)
                      decoded: https://github.com/ollama/ollama/blob/main/server/images.go#L245
                  and `layers`, interesting
                      "application/vnd.ollama.image.[model|system|template|license]"
                      not actual layers
                      one has system prompt
                          cat $HOME/.ollama/models/blobs/sha256-66b9ea09bd5b7099cbb4fc820f31b575c0366fa439b08245566692c6784e281e
                      one is a template
                          cat $HOME/.ollama/models/blobs/sha256-e94a8ecb9327ded799604a2e478659bc759230fe316c50d686358f932f52776c
                      one is a license
                          cat ~/.ollama/models/blobs/sha256-832dd9e00a68dd83b3c3fb9f5588dad7dcf337a0db50f7d9483f310cd292e92e
                      one is of course the data
                          sha256-60e05f2100071479f596b964f89f510f057ce397ea22f2833a0cfe029bfc2463
                      OTHER LAYER TYPES TOO:
                          https://github.com/ollama/ollama/blob/main/server/images.go#L262
                      OH CRAP OK... here is where model params come from!
                          https://github.com/ollama/ollama/blob/main/server/images.go#L297
                          decodes options from  "application/vnd.ollama.image.params":
                          SO, IIUC in case of qwen2.5-coder, it doesn't have any parameters file so it must just use defaults?
                              OK just found my custom model (via Modelfile) and it has params file!
                                  "application/vnd.ollama.image.params"
                          SEARCH for models w/ params:
                              ag vnd.ollama.image.params $HOME/.ollama/models/manifests/registry.ollama.ai/library
                                  YUP!!! none of the qwen2.5-coder models have a params file but...
                              llama3.2 does, so does deepseek-r1, deepseek-coder-v2
                               deepseek-r1/7b params
                                  cat /Users/wesdemos/.ollama/models/manifests/registry.ollama.ai/library/deepseek-r1/7b | jq
                                      "sha256:f4d24e9138dd4603380add165d2b0d970bef471fac194b436ebd50e6147c6588"
                                      cat $HOME/.ollama/models/blobs/sha256-f4d24e9138dd4603380add165d2b0d970bef471fac194b436ebd50e6147c6588 | jq
                                            {
                                              "stop": [
                                                "<｜begin▁of▁sentence｜>",
                                                "<｜end▁of▁sentence｜>",
                                                "<｜User｜>",
                                                "<｜Assistant｜>"
                                              ]
                                            }



           modelOptions() used to setup runner options
              https://github.com/ollama/ollama/blob/main/server/routes.go#L66
              starts with DefaultOptions() just like interface below for `generate` requests
                 that means the same defaults are used by `legacy` too
              then, it uses the model's "options" (IIUC defaults)
                  [`FromMap(model.Options)`](https://github.com/ollama/ollama/blob/main/api/types.go#L496)
              finally, uses request options as last step, using SAME CODE in `FromMap`
                  `FromMap(requestOpts)`
           [GetRunner](https://github.com/ollama/ollama/blob/main/server/sched.go#L81) is called w/ options and model
              - defaults [`NumCtx = 4`](https://github.com/ollama/ollama/blob/main/server/sched.go#L82)
              - basically maps to [`LlmRequest`](https://github.com/ollama/ollama/blob/main/server/sched.go#L24)
                  - notably, with `opts` (api.Options)

           TODO => concerning... does this code say if `Raw` then don't tokenize the prompt?
               https://github.com/ollama/ollama/blob/main/server/routes.go#L324

           Completion used to get completion
               [here](https://github.com/ollama/ollama/blob/main/server/routes.go#L295) is the call in GenerateHandler
                  (points to interface) on llama "server"
               [IMPL](https://github.com/ollama/ollama/blob/main/llm/server.go#L684)
                   THIS is the money shot!
                   all options mapped immediately
                   here I can see args passed to llama-server (its equivalent in ollama)
                   client closes connection => [abort](https://github.com/ollama/ollama/blob/main/llm/server.go#L733)
                   num_predict must be <= 10 * num_ctx
                   calls `/completion` on llama-server (from llama.cpp)
                       https://github.com/ggerganov/llama.cpp/blob/fd08255d0dea6625596c0367ee0a11d195f36762/examples/server/public_legacy/completion.js#L15
                       https://github.com/ggerganov/llama.cpp/blob/master/examples/server/README.md?plain=1#L1035
                       FYI llama-server now has `/infill` too
                           https://github.com/ggerganov/llama.cpp/blob/master/examples/server/README.md?plain=1#L638
                               I could use this directly (bypass ollama) but I am not sure I am convinced of its prompt style..
                               it uses <|file_sep and <|repo_name w/ hardcoded values so that might not be what I want









           FYI can pass empty request (prompt = "") to load a runner only
           Pass KeepAlive = nil => unload
        - then, if not raw
           - use Prompt/Suffix only for FIM
           - else everything is put into Messages (System/Context/images/Messages)
    - legacy adds (wraps) [CompletionsMiddleware](https://github.com/ollama/ollama/blob/main/openai/openai.go#L867)
        - calls into [fromCompleteRequest](https://github.com/ollama/ollama/blob/main/openai/openai.go#L529)
            - this maps `CompletionRequest` => `GenerateRequest` for the legacy endpoint
                - FYI [`CompletionRequest`](https://github.com/ollama/ollama/blob/main/openai/openai.go#L119)
            - OMFG... it only copies over a few fields... gah...
                 - it even uses same container GenerateRequest...
                 - but only allows a few fields to be used!
            - only copies over:
                 - stop, num_predict, temperature, seed, frequency_penalty, presence_penalty, top_p
                 - gahh... this method literally builds an Options object! so it could allow you to pass yours instead!!! GAHHH
                     - https://github.com/ollama/ollama/blob/main/openai/openai.go#L571
        - THAT IS IT, pretty much everything else is the same with `legacy` handling... just a subset of options
            - presumably, only allows params that are compatible with OpenAI API...
                - https://platform.openai.com/docs/api-reference/completions/create#completions-create
                - why though, b/c OpenAI API allows other params that aren't supported, so why not do the same with ollama for key params you can use with `generate` endpoint?

## Request/Response Types

[GenerateRequest](/Users/wesdemos/.local/share/nvim/lazy/plenary.nvim`) body of request (for `generate`)
- `model`

- `prompt`
- `suffix` for FIM
- `system` override? IIAC does not apply to FIM?
- `template` pass a new template (override)
- `raw` or bypass template

- `context` from previous call (is deprecated, IIAC you need to use message history instead)
- `stream` - vs sync

- `format` of the response (structured outputs?)
- `keep_alive` - after request, how long to keep model in memory
    - TODO try this instead of 30 minute override I set
- `images`
- `options` - dict -  model parameters (i.e. num_ctx)
    - [general](https://github.com/ollama/ollama/blob/main/api/types.go#L209)
        [default options](https://github.com/ollama/ollama/blob/main/api/types.go#L590)
        // Predict options used at runtime
        NumKeep          int      `json:"num_keep,omitempty"`
        Seed             int      `json:"seed,omitempty"`
        NumPredict       int      `json:"num_predict,omitempty"`
        TopK             int      `json:"top_k,omitempty"`
        TopP             float32  `json:"top_p,omitempty"`
        MinP             float32  `json:"min_p,omitempty"`
        TypicalP         float32  `json:"typical_p,omitempty"`
        RepeatLastN      int      `json:"repeat_last_n,omitempty"`
        Temperature      float32  `json:"temperature,omitempty"`
        RepeatPenalty    float32  `json:"repeat_penalty,omitempty"`
        PresencePenalty  float32  `json:"presence_penalty,omitempty"`
        FrequencyPenalty float32  `json:"frequency_penalty,omitempty"`
        Mirostat         int      `json:"mirostat,omitempty"`
        MirostatTau      float32  `json:"mirostat_tau,omitempty"`
        MirostatEta      float32  `json:"mirostat_eta,omitempty"`
        Stop             []string `json:"stop,omitempty"`

    - `Runner` related https://github.com/ollama/ollama/blob/main/api/types.go#L232
        // Runner options which must be set when the model is loaded into memory
        type Runner struct {
            NumCtx    int   `json:"num_ctx,omitempty"`
            NumBatch  int   `json:"num_batch,omitempty"`
            NumGPU    int   `json:"num_gpu,omitempty"`
            MainGPU   int   `json:"main_gpu,omitempty"`
            LowVRAM   bool  `json:"low_vram,omitempty"`
            F16KV     bool  `json:"f16_kv,omitempty"` // Deprecated: This option is ignored
            LogitsAll bool  `json:"logits_all,omitempty"`
            VocabOnly bool  `json:"vocab_only,omitempty"`
            UseMMap   *bool `json:"use_mmap,omitempty"`
            UseMLock  bool  `json:"use_mlock,omitempty"`
            NumThread int   `json:"num_thread,omitempty"`
        }

[GenerateResponse](https://github.com/ollama/ollama/blob/main/api/types.go#L435) body of response (for `generate`)







