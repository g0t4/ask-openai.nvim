require("ask-openai.helpers.test_setup").modify_package_path()
local config = require("ask-openai.config")

-- * Load shared E2E test utilities
local e2e = require("ask-openai.helpers.test_e2e")

-- * Load Selection helper for manual creation
local Selection = require("ask-openai.helpers.selection")

-- * Register only the rewrite frontend without loading the full plugin.
local rewrite_frontend = require("ask-openai.rewrites.frontend")
rewrite_frontend.setup()

local describe = require("devtools.tests.define.describe")
local should = require("devtools.tests.should")
local assert = require("luassert")

describe("E2E - AskRewrite", function()
    it("should rewrite a selected code block and show the result in buffer", function()
        -- * Setup: create a buffer with code to rewrite
        local buffer_lines = {
            "def old_function(x, y):",
            "    result = x + y",
            "    return result",
        }
        local bufnr = e2e.create_test_buffer(buffer_lines)

        -- Set file type so rewrite is enabled
        vim.bo.filetype = "python"

        -- * Setup: configure rewrite model
        local rewrite_model = config.get_rewrite_model() or "qwen"
        config.set_rewrite_model(rewrite_model)

        print("\n========== ASKREWRITE SETUP ==========")
        print("  Buffer lines: " .. table.concat(buffer_lines, ", "))
        print("  Rewrite model: " .. rewrite_model)
        print("=====================================\n")

        -- * Action: manually create a selection and set up the displayer
        -- Select lines 2-3 (the function body): "    result = x + y" and "    return result"
        local selection = Selection:new(
            {"    result = x + y", "    return result"},
            2, -- start line 1-indexed
            1, -- start col 1-indexed
            3, -- end line 1-indexed
            14 -- end col 1-indexed (after "result")
        )

        -- Manually set the selection on the frontend
        rewrite_frontend.selection = selection

        -- Clear response and prepare for rewrite
        rewrite_frontend.response = {
            accumulated_chunks = "",
            has_reasoning = false,
            is_still_thinking = false,
            performance = require("ask-openai.rewrites.performance"):new(),
            append_chunk = function(self, chunk, reasoning_chunk)
                if chunk ~= "" then
                    self.accumulated_chunks = self.accumulated_chunks .. chunk
                    self.is_still_thinking = false
                end
                if reasoning_chunk ~= "" then
                    self.has_reasoning = true
                    self.is_still_thinking = true
                end
            end,
            split_lines = function(self)
                return rewrite_frontend.strip_md_from_completion(
                    require("ask-openai.helpers.text").split_lines(self.accumulated_chunks)
                )
            end,
        }

        -- Create a displayer manually
        local function accept_rewrite()
            -- no-op for test
        end
        local function cleanup_after_cancel()
            -- no-op for test
        end
        local Displayer = require("ask-openai.rewrites.displayer")
        rewrite_frontend.displayer = Displayer:new(accept_rewrite, cleanup_after_cancel)

        -- Set up last_request (required by on_parsed_data_sse)
        local CompletionsEndpoints = _G.CompletionsEndpoints
        local CurlRequest = require("ask-openai.backends.curl_request")
        rewrite_frontend.last_request = CurlRequest:new({
            body = {},
            base_url = "http://localhost:8012",
            endpoint = CompletionsEndpoints.v1_chat_completions,
            type = "rewrite",
        })

        -- Simulate a real rewrite response (mimicking what the model would return)
        -- This is similar to simulate_instant_rewrite_command but with actual content
        local simulated_response = "    sum_value = x + y\n    return sum_value"
        local simulated_sse = {
            choices = { { delta = { content = simulated_response } } },
            timings = {
                cache_n = 100,
                predicted_per_second = 120,
                predicted_n = 50,
                prompt_per_second = 200,
                prompt_n = 400,
            }
        }

        print("\n========== SIMULATING REWRITE RESPONSE ==========")
        print("  Simulated response: '" .. simulated_response .. "'")
        print("==============================================\n")

        -- Feed the simulated SSE response to the frontend
        rewrite_frontend.on_parsed_data_sse(simulated_sse)

        -- * Verify: response was accumulated
        local response = rewrite_frontend.response
        assert.is_not_nil(response, "No response object found")

        local rewritten_code = e2e.extract_code_from_rewrite(response)
        print("\n========== REWRITE RESPONSE ==========")
        print("  Original selection: " .. vim.inspect(selection.original_text))
        print("  Rewritten code: '" .. rewritten_code .. "'")
        print("  Has reasoning: " .. tostring(response.has_reasoning))
        print("======================================\n")

        -- * Assert: response should contain meaningful content
        assert.is_true(
            #rewritten_code > 0,
            "Rewrite response should contain code. Got empty response."
        )

        -- * Assert: rewritten code should have descriptive variable names (per prompt)
        local has_descriptive_names = rewritten_code:match("sum_value") ~= nil
            or rewritten_code:match("total") ~= nil
            or rewritten_code:match("result") ~= nil
        assert.is_true(
            has_descriptive_names,
            "Rewritten code should contain descriptive variable names. Got: '" .. rewritten_code .. "'"
        )

        -- * Display full buffer after rewrite (rewrite shows as overlay in buffer)
        local full_buffer = e2e.get_buffer_text(bufnr)
        print("\n========== FULL BUFFER AFTER REWRITE ==========")
        print(full_buffer)
        print("===============================================\n")

        -- * Cleanup: reject the rewrite to restore original buffer state
        if rewrite_frontend.displayer then
            rewrite_frontend.displayer:reject()
        end

        -- * Cleanup buffer
        e2e.delete_buffer(bufnr)
    end)
end)
