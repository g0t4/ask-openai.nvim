require("ask-openai.helpers.test_setup").modify_package_path()
local metadata = require("ask-openai.backends.response_metadata")

-- TODO review what I even need of this later on ... if I keep my tracing logic
-- plan is to move to python based langchain clients for even my neovim AI tooling so I can standardize on one AI client fwk and reuse all that goodness that we setup with langchain ChatOpenAICompatible chat model client
-- FYI when I removed the last_sse from traces I didn't review which of these tests are redundant and/or not needed anymore I just removed usages of last_sse in them

describe("verbatim response metadata", function()
    it("ignores null usage and continuous usage on content chunks", function()
        local saved = {}
        metadata.accumulate({ usage = {}, metrics = vim.NIL }, saved)
        assert.equals(nil, saved.metrics)
    end)

    it("merges SGLang's extension and usage chunks without mutating either", function()
        local extension = {
            choices = {},
            usage = vim.NIL,
            sglext = {
                spec_tokens_details = {
                    spec_num_correct_drafts = 12,
                    spec_num_proposed_drafts = 18,
                    spec_accept_rate = 2 / 3,
                    spec_accept_length = 8 / 3
                }
            }
        }
        local usage = {
            choices = {},
            sglext = vim.NIL,
            usage = {
                prompt_tokens = 14,
                completion_tokens = 16,
                reasoning_tokens = 9,
                prompt_tokens_details = { cached_tokens = 4 }
            }
        }
        local messages = { { role = "assistant", content = "OK" } }
        local saved = {}
        --
        -- accumulate across all SSEs
        metadata.accumulate(extension, saved)
        metadata.accumulate(usage, saved)
        --
        assert.equals("sglang", saved.backend)
        assert.equals(12, saved.sglext.spec_tokens_details.spec_num_correct_drafts)
    end)
end)

describe("usage-triggered trace logging", function()
    local logger, original_save
    before_each(function()
        logger = require("ask-openai.logs.completion_logger")
        original_save = logger.save_trace
    end)
    after_each(function()
        logger.save_trace = original_save
    end)

    it("saves accumulated content and verbatim usage/metrics without timings", function()
        local saved
        logger.save_trace = function(_, _, messages)
            saved = { messages = messages }
        end
        local request = { body = { messages = {} } }
        local function emit(sse) logger.log_sse_to_request(sse, request, {}) end
        emit({ choices = { { delta = { role = "assistant", reasoning = "first " } } } })
        emit({ choices = { { delta = { reasoning_content = vim.NIL, reasoning = "second" } } } })
        emit({ choices = { { delta = { content = "OK" } } }, usage = vim.NIL })
        emit({ choices = { { delta = {}, finish_reason = "stop" } } })
        assert.is_nil(saved)
        local final = { choices = {}, usage = { total_tokens = 8 }, metrics = { tokens_per_second = 11.7 } }
        emit(final)
        assert.is_true(vim.wait(1000, function() return saved ~= nil end, 10))
        assert.equals("OK", saved.messages[1].content)
        assert.equals("first second", saved.messages[1].reasoning_content)
        assert.equals("stop", saved.messages[1].finish_reason)
        assert.equals(final.usage, saved.messages[1].usage)
        assert.equals(final.metrics, saved.messages[1].metrics)
    end)
    it("saves SGLang stats after separate terminal chunks even without timings", function()
        local saved
        logger.save_trace = function(_, _, messages) saved = { messages = messages } end
        local request = { body = { messages = {} } }
        logger.log_sse_to_request({ choices = { { delta = { role = "assistant", content = "OK" } } } }, request, {})
        local spec = { spec_tokens_details = { spec_num_correct_drafts = 12, spec_num_proposed_drafts = 18 } }
        logger.log_sse_to_request({ choices = {}, usage = vim.NIL, sglext = spec }, request, {})
        logger.log_sse_to_request({
            choices = {},
            usage = {
                prompt_tokens = 14,
                completion_tokens = 16,
                reasoning_tokens = 9
            },
            sglext = vim.NIL
        }, request, {})
        assert.is_true(vim.wait(1000, function()
            return saved and type(saved.messages[1].usage) == "table"
        end, 10))
        assert.equals("OK", saved.messages[1].content)
        assert.equals(16, saved.messages[1].usage.completion_tokens)
        assert.same(spec, saved.messages[1].sglext)
        assert.equals("sglang", saved.messages[1].backend)
    end)
end)
