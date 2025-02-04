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
           modelOptions() used to setup runner options
              https://github.com/ollama/ollama/blob/main/server/routes.go#L66
              starts with DefaultOptions() just like interface below for `generate` requests
                 that means the same defaults are used by `legacy` too

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







