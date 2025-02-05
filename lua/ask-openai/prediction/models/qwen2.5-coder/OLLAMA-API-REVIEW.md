## review of ollama APIs, and indirectly llama-server as well

Endpoints of note:
- `/api/generate`  (ollama specific endpoint)
    - hereafter referred as `generate`
- `/v1/completions`  (aka legacy openai completions)
    - hereafter referred to as `legacy`

Behind the scenes ollama spins up a `llama-server` instance per model, when requested

## TODO - Capture recommended ollama command to set model parameters for completion
- OLLAMA_NUM_PARALLEL=1
- OLLAMA_HOST
- Model params
    - where to configure:
        - model itself has a `params` layer with json file of parameter names/values
            - usually few, if any, have any set though
        - via env vars
            - [available env vars](https://github.com/ollama/ollama/blob/main/envconfig/config.go#L236)
            - via `/api/generate`
            - or, Modelfile (if using `/v1/completions` and IIAC `/v1/chat/completions`
        - via API requests
            - `num_ctx` (defaults to 2048) => and in my testing, many models don't override it
        - via CLI args (i.e. ollama run has set param command)
        - indirectly via runner
            - moreso to validate correct config with above methods
            - runner's args: https://github.com/ollama/ollama/blob/main/llama/runner/runner.go#L891
                - equivalent to `llama-server` for ollama's purposes
- Runner recomendations:
    - model: qwen2.5-Coder:7b-instruct_q8_0
    - num_gpu/NumGPU: 1000  (set higher than model layers to make sure as many as possible are in gpu)
    - batch size:
        - physical:
            - NumBatch:
            - TODO double check this is physical and not logical
            - `-ub 1024` for llama-server
        - logical:

            - `-b 1024` for llama-server
    - b:
    - NumCtx/num_ctx: defaults 2048

    - cache-reuse:
    - CHECK log output for what params are used to start runner, to confirm correct config:
        level=INFO source=server.go:376 msg="starting llama server" cmd="/usr/lib/ollama/runners/rocm_avx/ollama_llama_server runner --model /home/wes/.ollama/models/blobs/sha256-24b532e5276503b147d0eea0e47cb1d2bcce7c9034edd657b624261862ca54a1 --ctx-size 2048 --batch-size 512 --n-gpu-layers 29 --threads 8 --parallel 1 --port 36747"
    - TODO try these args:
        - `UseMMap`
            - and/or `UseMLock`
        - `verbose` runner arg
        - `NumThread` ?
        - `MainGPU`
    - BTW runner sets args [here](https://github.com/ollama/ollama/blob/main/llama/runner/runner.go#L836)
- Request recommendations:
    - NumPredict: ?
    - Seed: ?
    - Temperature: ?


```bash
llama-server \
    -hf ggml-org/Qwen2.5-Coder-7B-Q8_0-GGUF \
    --port 8012 -ngl 99 -fa -ub 1024 -b 1024 \
    --ctx-size 0 --cache-reuse 256
```



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
                  - FYI here is runner after making first request
                      /usr/lib/ollama/runners/rocm_avx/ollama_llama_server runner \
                          --model /home/wes/.ollama/models/blobs/sha256-24b532e5276503b147d0eea0e47cb1d2bcce7c9034edd657b624261862ca54a1 \
                          --ctx-size 2048 --batch-size 512 --n-gpu-layers 29 --threads 8 --parallel 1 --port 43607
                          # FYI this looks to be `cmd/runner`'s exe (run `go build`):
                              ./cmd/runner/runner --help # shows same args
           TODO => concerning... does this code say if `Raw` then don't tokenize the prompt?
               https://github.com/ollama/ollama/blob/main/server/routes.go#L324

           Completion() used to get completion
               [here](https://github.com/ollama/ollama/blob/main/server/routes.go#L295) is the call in GenerateHandler
                  (points to interface) on llama "server"
               [IMPL](https://github.com/ollama/ollama/blob/main/llm/server.go#L684)
                   this Completion( func is in the `llama serve` process
                      and it calls out to `runner`'s `completion` func
                         here is the [HTTP request to /completion](https://github.com/ollama/ollama/blob/main/llm/server.go#L763)
                   client closes connection => [abort](https://github.com/ollama/ollama/blob/main/llm/server.go#L733)
                   num_predict must be <= 10 * num_ctx
                   lolz... hardcodes token repeat limit to 30
                       says "modify as needed"
                       https://github.com/ollama/ollama/blob/main/llm/server.go#L821
                   if hits length limit (num_predict) =>
                       sets `stop` = [`length`](https://github.com/ollama/ollama/blob/main/llm/server.go#L837)
               Runner side:
                   `/completion` maps to llama/runner/runner.go:
                       [`completion`](https://github.com/ollama/ollama/blob/main/llama/runner/runner.go#L604) /completion endpoint
                       IIAC this is similar to whatever in llama-server would've been used
                       `runner` has similar args
                           and its readme suggests that is the purpose too:
                              /cmd/runner, see README.md
                   SO, this doesn't direclty use `llama-server`... instead it has its own `runner` that is per model instance
                       "ollama serve" => "server"
                       runners => one per model (a backend server if you will)...
                          AFAICT serve uses http to contact runner...
                             confirmed by the fact that there are multiple ollama processes
                             `ollama serve`
                                 \_ ollama_llama_server runner --model ...


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





## Flash Attention Testing

- TODO test on mbp21 too (tonight) and see if it works well with Metal backend
- TODO does this work better with nvidia only?
    - this was with an AMD GPU btw (which does well overall but not with FA, not yet)

Notes:
- OLLAMA_FLASH_ATTENTION=1 (only via env var currently, IIUC)
- only works with GPUs IIUC, not CPU... check logs to see if not supported warning
- `kvCacheType` for quantizing this but IIUC not wise with Qwen2 models
    - plus, quantizing the KV cache `OLLAMA_KV_CACHE_TYPE` => however Qwen2 has high GQA so maybe this is not wise

- FYI used `llama-bench` with qwen2.5-coder models
    - w/ `-fa=1` was worse performance in every case tested:
    - `-p 512 -n 128` defaults => worse
    - `-p 4096 -n 4096` => worse

```sh
./build/bin/llama-bench -p 4096 -n 4096 -fa 0,1 \
    -m models/qwen2.5-coder-3b-instruct-q4_k_m.gguf,models/qwen2.5-coder-3b-instruct-q8_0.gguf,models/qwen2.5-coder-7b-instruct-q4_k_m.gguf \
    -m models/qwen2.5-coder-7b-instruct-q8_0.gguf \
    -m models/qwen2.5-coder-14b-instruct-q4_k_m.gguf \
    -m models/qwen2.5-coder-32b-instruct-q4_k_m.gguf \
    -m models/qwen2.5-coder-0.5b-instruct-q8_0.gguf  \
    -m models/qwen2.5-coder-0.5b-instruct-q4_k_m.gguf  \
    -m models/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf  \
    -m models/qwen2.5-coder-1.5b-instruct-q8_0.gguf
# FYI 32b model failed to load, must be corrupt
```
```log
  Device 0: AMD Radeon RX 6900 XT, gfx1030 (0x1030), VMM: no, Wave Size: 32
| model                          |       size |     params | backend    | ngl | fa |          test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -: | ------------: | -------------------: |
| qwen2 3B Q4_K - Medium         |   1.95 GiB |     3.40 B | ROCm       |  99 |  0 |        pp4096 |       2016.93 ± 5.44 |
| qwen2 3B Q4_K - Medium         |   1.95 GiB |     3.40 B | ROCm       |  99 |  0 |        tg4096 |         97.20 ± 0.00 |
| qwen2 3B Q4_K - Medium         |   1.95 GiB |     3.40 B | ROCm       |  99 |  1 |        pp4096 |       1195.44 ± 0.69 |
| qwen2 3B Q4_K - Medium         |   1.95 GiB |     3.40 B | ROCm       |  99 |  1 |        tg4096 |         62.44 ± 0.04 |
| qwen2 3B Q8_0                  |   3.36 GiB |     3.40 B | ROCm       |  99 |  0 |        pp4096 |       2376.33 ± 3.15 |
| qwen2 3B Q8_0                  |   3.36 GiB |     3.40 B | ROCm       |  99 |  0 |        tg4096 |         77.07 ± 0.01 |
| qwen2 3B Q8_0                  |   3.36 GiB |     3.40 B | ROCm       |  99 |  1 |        pp4096 |       1343.55 ± 2.00 |
| qwen2 3B Q8_0                  |   3.36 GiB |     3.40 B | ROCm       |  99 |  1 |        tg4096 |         53.52 ± 0.01 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | ROCm       |  99 |  0 |        pp4096 |       1127.95 ± 5.19 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | ROCm       |  99 |  0 |        tg4096 |         65.15 ± 0.08 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | ROCm       |  99 |  1 |        pp4096 |        788.59 ± 0.59 |
| qwen2 7B Q4_K - Medium         |   4.36 GiB |     7.62 B | ROCm       |  99 |  1 |        tg4096 |         52.50 ± 0.05 |
| qwen2 7B Q8_0                  |   7.54 GiB |     7.62 B | ROCm       |  99 |  0 |        pp4096 |       1381.53 ± 3.80 |
| qwen2 7B Q8_0                  |   7.54 GiB |     7.62 B | ROCm       |  99 |  0 |        tg4096 |         47.63 ± 0.01 |
| qwen2 7B Q8_0                  |   7.54 GiB |     7.62 B | ROCm       |  99 |  1 |        pp4096 |        932.38 ± 4.21 |
| qwen2 7B Q8_0                  |   7.54 GiB |     7.62 B | ROCm       |  99 |  1 |        tg4096 |         40.35 ± 0.01 |
```

