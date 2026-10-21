require("ask-openai.helpers.test_setup").modify_package_path()
local models = require("ask-openai.config.models")
local params = require("ask-openai.agents.models.params")

describe("DeepSeek actual model token defaults", function()
    local function body(actual_model_name, backend, overrides)
        return params.body_for(models.DEEPSEEK, vim.tbl_extend("force", { messages = {} }, overrides or {}),
            models.THINKING_OFF, { backend = backend, actual_model_name = actual_model_name })
    end

    it("keeps the existing v4 limit and omits it only for actual v4.1 Flash", function()
        assert.equals(393216, body("ggml-org/DeepSeek-V4-Flash-0731-GGUF", "llama-server").max_tokens)
        assert.equals(393216, body("deepseek-v4-flash", "vllm").max_tokens)
        assert.is_nil(body("deepseek-v4.1-flash", "vllm").max_tokens)
        assert.is_nil(body("deepseek-ai/DeepSeek-V4.1-Flash", "llama-server").max_tokens)
        assert.equals(393216, body(nil, "unknown").max_tokens)
        assert.equals(393216, params.body_for(models.DEEPSEEK, { messages = {} }, models.THINKING_OFF).max_tokens)
    end)

    it("preserves explicit overrides and vLLM usage options", function()
        local request = body("deepseek-v4.1-flash", "vllm", { max_tokens = 512 })
        assert.equals(512, request.max_tokens)
        assert.is_true(request.stream_options.include_usage)
    end)
end)
