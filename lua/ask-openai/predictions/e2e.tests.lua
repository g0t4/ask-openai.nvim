require("ask-openai.helpers.test_setup").modify_package_path()

--- Wait for a condition to become true, polling every `poll_ms` milliseconds.
--- @param predicate fun(): boolean
--- @param timeout_ms number Maximum time to wait in milliseconds
--- @param poll_ms number Time between polls in milliseconds
--- @return boolean success Whether the condition became true before timeout
local function wait_for(predicate, timeout_ms, poll_ms)
    poll_ms = poll_ms or 100
    local start_time = vim.uv.hrtime() / 1e6

    while true do
        if predicate() then
            return true
        end

        local elapsed = vim.uv.hrtime() / 1e6 - start_time
        if elapsed >= timeout_ms then
            return false
        end

        -- Yield to let async operations (SSE, timers) process
        vim.wait(poll_ms)
    end
end

-- * Register only the predictions frontend without loading the full plugin.
local predictions_frontend = require("ask-openai.predictions.frontend")
predictions_frontend.start_predictions()

-- * Wait for MCP servers to initialize (needed for RAG context in FIM requests)
local mcp_tools = require("ask-openai.tools.mcp")

print("\n========== WAITING FOR MCP SERVERS TO INITIALIZE ==========")
local mcp_ready = wait_for(function()
    return mcp_tools.ready
end, 50000, 500) -- 50 second timeout, poll every 500ms

if mcp_ready then
    print("  MCP servers are ready!")
else
    print("  WARNING: MCP servers did not initialize within timeout")
end
print("==========================================================\n")

local describe = require("devtools.tests.define.describe")
local should = require("devtools.tests.should")
local assert = require("luassert")

describe("E2E - FIM predictions", function()
    it("should get a prediction when triggered from a code buffer", function()
        -- * Setup: create a buffer with code and position cursor
        local buffer_lines = {
            "def add(x, y):",
            "    ", -- cursor will be here, expecting "return x + y"
        }
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, buffer_lines)
        vim.api.nvim_win_set_buf(0, bufnr)
        vim.api.nvim_win_set_cursor(0, { 2, 4 }) -- cursor after 4 spaces on line 2

        -- Set file type so predictions are enabled (not in ignore list)
        vim.bo.filetype = "python"

        -- * Setup: configure FIM model
        local api = require("ask-openai.api")
        local fim_model = api.get_fim_model() or "qwen"
        api.set_fim_model(fim_model)

        print("\n========== TRIGGERING FIM PREDICTION ==========")
        print("  Buffer lines: " .. table.concat(buffer_lines, ", "))
        print("  Cursor: line 2, col 4")
        print("  FIM model: " .. fim_model)
        print("==============================================\n")

        -- * Action: trigger prediction manually (bypassing event system)
        predictions_frontend.ask_for_prediction()

        -- * Wait for the prediction to complete
        -- The prediction completes when current_prediction has chunks or is done
        local prediction_ready = wait_for(function()
            local current = predictions_frontend.current_prediction
            if not current then
                return false
            end
            -- Check if prediction has accumulated text
            return current.prediction ~= nil and current.prediction ~= ""
        end, 30000, 200) -- 30 second timeout, poll every 200ms

        -- * Verify: prediction was created and has content
        assert.is_true(
            prediction_ready,
            "Prediction did not complete within timeout period. Current prediction state:\n"
            .. vim.inspect(predictions_frontend.current_prediction)
        )

        local current_prediction = predictions_frontend.current_prediction
        assert.is_not_nil(current_prediction, "No prediction object created")

        -- * Assert: prediction should have accumulated text
        assert.is_true(
            #current_prediction.prediction > 0,
            "Prediction should contain text. Got empty prediction.\n"
            .. vim.inspect(current_prediction)
        )

        -- * Display the prediction for debugging
        print("\n========== PREDICTION RESULT ==========")
        print("  Prediction text: '" .. current_prediction.prediction .. "'")
        print("  Has duplicate prefix: " .. tostring(current_prediction.has_duplicate_prefix))
        print("  First line: '" .. (current_prediction.first_line or "(none)") .. "'")
        print("======================================\n")

        -- * Assert: prediction should be meaningful code (not just whitespace)
        local has_code_content = current_prediction.prediction:match("[%w_]") ~= nil
        assert.is_true(
            has_code_content,
            "Prediction should contain code content (alphanumeric characters). Got: '"
            .. current_prediction.prediction .. "'"
        )

        -- * Cleanup: cancel the prediction to free resources
        predictions_frontend.cancel_current_prediction()

        -- * Cleanup buffer
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
end)
