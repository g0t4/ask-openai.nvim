## model notes from FIM

        -- https://huggingface.co/collections/JetBrains/mellum-68120b4ae1423c86a2da007a
        -- model = "huggingface.co/JetBrains/Mellum-4b-base-gguf", -- no language specific fine tuning
        -- model = "huggingface.co/JetBrains/Mellum-4b-sft-python-gguf", -- ** did better with Lua than base!
        -- kotlin exists but no gguf on hf yet:
        --   https://huggingface.co/JetBrains/Mellum-4b-sft-kotlin
        -- TODO add in other fine tunes for languages as released

        -- FYI set of possible models for demoing impact of fine tune
        -- qwen2.5-coder:7b-base-q8_0  -- ** shorter responses, more "EOF" focused
        -- qwen2.5-coder:14b-base-q8_0 -- ** shorter responses, more "EOF" focused
        -- qwen2.5-coder:7b-instruct-q8_0 -- DO NOT USE instruct
        -- model = "qwen2.5-coder:7b-base-q8_0", -- ** favorite
        --
        -- model is NOT ACTUALLY USED when hosting llama-server
        -- model = "huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q4_K_M",
        -- model = "qwen3-coder:30b-a3b-fp16", -- ** TODO TRY THIS ONE
        -- # TODO optimal params? any new updates for llama-server that would help?
        -- llama-server -hf unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q4_K_M --host 0.0.0.0 --port 8012 --batch-size 2048 --ubatch-size 2048 --flash-attn --n-gpu-layers 99
        -- TODO params.n_ctx = 0;
        -- REMEMBER just host the model in llama-server, it only runs one


        -- model = "gpt-oss:20b",

        -- starcoder2:15b-instruct-v0.1-q8_0                      a11b58c111d9    16 GB     6 weeks ago
        -- starcoder2:15b-q8_0                                    95f55571067f    16 GB     6 weeks ago
        -- starcoder2:7b-fp16                                     f0643097e171    14 GB     6 weeks ago
        -- starcoder2:3b-q8_0                                     003abcecad23    3.2 GB    6 weeks ago
        -- starcoder2:7b-q8_0                                     d76878e96d8a    7.6 GB    6 weeks ago
        -- model = "starcoder2:7b-q8_0",

        -- codellama:7b-code-q8_0 -- shorter too
        -- codellama:7b-instruct-q8_0 -- longer too
        -- codellama:7b-python-q8_0 -- doesn't do well with FIM (spits out FIM tokens text as if not recognized)... also not sure it supports FIM based on reading docs only code/instruct are mentioned for FIM support)
        -- model = "codellama:7b-code-q8_0",

        -- llama3.1:8b-text-q8_0 -- weird, generated some "code"/text in this file that wasn't terrible!... verbose
        -- llama3.1:8b-instruct-q8_0
        -- model = "llama3.1:8b-instruct-q8_0",
        -- https://github.com/meta-llama/codellama/blob/main/llama/generation.py#L496

        -- model = "codestral:22b-v0.1-q4_K_M",

        -- model = "deepseek-coder-v2:16b-lite-base-q8_0", -- *** 217 TPS! WORKS GOOD!
        -- model = "deepseek-coder-v2:16b-lite-base-fp16", -- FITS! and its still fast (MoE)
