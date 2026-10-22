require("ask-openai.helpers.test_setup").modify_package_path()
local metadata = require("ask-openai.backends.response_metadata")

describe("verbatim response metadata", function()
    it("captures the empty-choices final chunk without changing fields", function()
        local sse = {
            choices = {},
            usage = { prompt_tokens = 6, completion_tokens = 2, total_tokens = 8 },
            metrics = { generation_time_ms = 52.29, speculative_decoding = { num_draft_tokens = 5 } },
        }
        local messages = { { content = "OK", finish_reason = "stop" } }
        assert.is_true(metadata.capture_final(sse, messages))
        assert.equals(sse, messages[1].last_sse)
        local saved = {}
        metadata.copy(messages[1].last_sse, saved)
        assert.equals(sse.usage, saved.usage)
        assert.equals(sse.metrics, saved.metrics)
        assert.is_nil(saved.timings)
        assert.equals("OK", messages[1].content)
    end)

    it("ignores null usage and continuous usage on content chunks", function()
        assert.is_false(metadata.is_final({ choices = {}, usage = vim.NIL }))
        assert.is_false(metadata.is_final({ choices = { { delta = { content = "hi" } } }, usage = {} }))
        assert.is_true(metadata.is_final({ timings = {} }))
        local saved = {}
        metadata.copy({ usage = {}, metrics = vim.NIL }, saved)
        assert.equals(vim.NIL, saved.metrics)
    end)

    it("does not attribute request totals to multiple choices", function()
        assert.is_false(metadata.capture_final({ choices = {}, usage = {} }, { {}, {} }))
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
        logger.save_trace = function(_, _, messages, last_sse)
            saved = { messages = messages, last_sse = last_sse }
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
        assert.equals(final, saved.last_sse)
        assert.equals("OK", saved.messages[1].content)
        assert.equals("first second", saved.messages[1].reasoning_content)
        assert.equals("stop", saved.messages[1].finish_reason)
        assert.equals(final.usage, saved.messages[1].usage)
        assert.equals(final.metrics, saved.messages[1].metrics)
    end)
end)
