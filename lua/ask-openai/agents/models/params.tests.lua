require("ask-openai.helpers.test_setup").modify_package_path()
local models = require("ask-openai.config.models")
local params = require("ask-openai.agents.models.params")

describe("DeepSeek actual model token defaults", function()
    local function body(actual_model_name, backend, overrides)
        return params.body_for(models.DEEPSEEK, vim.tbl_extend("force", { messages = {} }, overrides or {}),
            models.THINKING_OFF, { backend = backend, actual_model_name = actual_model_name })
    end

    it("leaves unspecified token limits to the server for both v4 and v4.1", function()
        assert.is_nil(body("ggml-org/DeepSeek-V4-Flash-0731-GGUF", "llama-server").max_tokens)
        assert.is_nil(body("deepseek-v4-flash", "vllm").max_tokens)
        assert.is_nil(body("deepseek-v4.1-flash", "vllm").max_tokens)
        assert.is_nil(body("deepseek-ai/DeepSeek-V4.1-Flash", "llama-server").max_tokens)
        assert.is_nil(body(nil, "unknown").max_tokens)
        assert.is_nil(params.body_for(models.DEEPSEEK, { messages = {} }, models.THINKING_OFF).max_tokens)
    end)

    it("preserves explicit overrides and vLLM usage options", function()
        local request = body("deepseek-v4.1-flash", "vllm", { max_tokens = 512 })
        assert.equals(512, request.max_tokens)
        assert.is_true(request.stream_options.include_usage)
    end)
    it("requests SGLang usage and speculative extensions for every configured model", function()
        for _, model in ipairs({ models.DEEPSEEK, models.GLM, models.GPTOSS }) do
            local original = { messages = {} }
            local request = params.body_for(model, original, models.THINKING_OFF,
                { backend = "sglang", actual_model_name = "glm-5.3-flash" })
            assert.is_true(request.stream_options.include_usage)
            assert.is_true(request.return_spec_tokens_details)
            assert.is_true(request.return_cached_tokens_details)
            assert.is_true(request.return_timings)
            assert.is_nil(original.return_spec_tokens_details)
        end
    end)

    it("only defaults timing extension for the patched GLM deployment", function()
        assert.is_nil(body("other-sglang-model", "sglang").return_timings)
        assert.is_nil(body("glm-5.3-flash", "vllm").return_timings)
        assert.is_false(body("glm-5.3-flash", "sglang", { return_timings = false }).return_timings)
    end)
end)
