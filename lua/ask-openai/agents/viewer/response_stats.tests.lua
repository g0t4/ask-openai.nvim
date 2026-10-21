local stats = require("ask-openai.agents.viewer.response_stats")

describe("raw backend response statistics display", function()
    it("shows vLLM usage and metrics with their own labels and no fabricated prefill rate", function()
        local response = {
            usage = { prompt_tokens = 100, completion_tokens = 20, total_tokens = 120,
                prompt_tokens_details = { cached_tokens = 80 },
                completion_tokens_details = { reasoning_tokens = 10 } },
            metrics = { time_to_first_token_ms = 118.64, generation_time_ms = 52.29,
                queue_time_ms = 0.02, mean_itl_ms = 52.29, tokens_per_second = 11.7,
                speculative_decoding = { num_draft_tokens = 5, num_accepted_draft_tokens = 1,
                    draft_acceptance_rate = 0.2, mean_acceptance_length = 2 } },
        }
        local original = vim.deepcopy(response)
        local rendered = table.concat(stats.format(response), "\n")
        for _, expected in ipairs({ "cached: 80", "in (includes cached): 100", "out: 20", "reasoning: 10",
            "TTFT: 118.6 ms", "queue: 0.0 ms", "decode: 52.3 ms", "mean ITL: 52.3 ms",
            "overall output: 11.7 tok/s", "draft: 1/5 accepted @ 20%", "mean acceptance length: 2.00" }) do
            assert.is_truthy(rendered:find(expected, 1, true), rendered)
        end
        assert.is_nil(rendered:find("prefill", 1, true))
        assert.equals(120, stats.total_tokens(response)) -- cached is already included
        assert.same(original, response)
    end)

    it("keeps llama-server input and output rates and cache-count semantics", function()
        local response = { timings = { cache_n = 80, prompt_n = 20, predicted_n = 10,
            prompt_per_second = 500, predicted_per_second = 100, draft_n = 0, draft_n_accepted = 0 } }
        local text = table.concat(stats.format(response), "\n")
        assert.is_truthy(text:find("in: 20 @ 500 tok/s", 1, true))
        assert.is_truthy(text:find("out: 10 @ 100 tok/s", 1, true))
        assert.is_nil(text:find("nan", 1, true))
        assert.equals(110, stats.total_tokens(response))
    end)

    it("shows usage without metrics and tolerates null and missing fields", function()
        local response = { usage = { prompt_tokens = 100, completion_tokens = 20,
            prompt_tokens_details = vim.NIL, completion_tokens_details = vim.NIL }, metrics = vim.NIL }
        assert.equals("in (includes cached): 100 | out: 20", table.concat(stats.format(response), "\n"))
        assert.equals(120, stats.total_tokens(response))
        assert.same({}, stats.format({ usage = vim.NIL, metrics = { time_to_first_token_ms = vim.NIL } }))
        assert.is_nil(stats.total_tokens({}))
    end)
end)
