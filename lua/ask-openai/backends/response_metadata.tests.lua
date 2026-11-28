require("ask-openai.helpers.test_setup").modify_package_path()
local metadata = require("ask-openai.backends.response_metadata")

-- TODO review what I even need of this later on ... if I keep my tracing logic
-- plan is to move to python based langchain clients for even my neovim AI tooling so I can standardize on one AI client fwk and reuse all that goodness that we setup with langchain ChatOpenAICompatible chat model client
-- FYI when I removed the last_sse from traces I didn't review which of these tests are redundant and/or not needed anymore I just removed usages of last_sse in them

describe("verbatim response metadata", function()
    it("merges SGLang's extension and usage chunks without mutating either", function()
        local sse_with_sglext = {
            choices = {},
            sglext = {
                spec_tokens_details = {
                    spec_num_correct_drafts = 12,
                    spec_num_proposed_drafts = 18,
                    spec_accept_rate = 2 / 3,
                    spec_accept_length = 8 / 3
                }
            }
        }
        local sse_with_timings_choices_and_usage = {
            choices = {},
            timings = {
                choices = {
                    -- TODO do I need to set anything here?
                }
            },
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
        -- FYI real order per testing
        -- finish_reason is first (not part of this accumulate_metadata)
        metadata.accumulate_metadata(sse_with_sglext, saved) -- then an SSE with sglext
        metadata.accumulate_metadata(sse_with_timings_choices_and_usage, saved) -- last, usage+timings.choices SSE
        --
        assert.equals("sglang", saved.metadata.backend)
        assert.equals(12, saved.metadata.sglext.spec_tokens_details.spec_num_correct_drafts)
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
        emit({ choices = { { delta = { reasoning_content = nil, reasoning = "second" } } } })
        emit({ choices = { { delta = { content = "OK" } } }, usage = nil })
        emit({ choices = { { delta = {}, finish_reason = "stop" } } })
        assert.is_nil(saved)
        local final = { choices = {}, usage = { total_tokens = 8 }, metrics = { tokens_per_second = 11.7 } }
        emit(final)
        assert.is_true(vim.wait(1000, function() return saved ~= nil end, 10))
        assert.equals("OK", saved.messages[1].content)
        assert.equals("first second", saved.messages[1].reasoning_content)
        assert.equals("stop", saved.messages[1].finish_reason)
        assert.equals(final.usage, saved.messages[1].metadata.usage)
        assert.equals(final.metrics, saved.messages[1].metadata.metrics)
    end)
end)
