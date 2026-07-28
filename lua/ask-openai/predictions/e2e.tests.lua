require("ask-openai.helpers.test_setup").modify_package_path()

-- * Load shared E2E test utilities
local e2e = require("ask-openai.helpers.test_e2e")

-- * Register only the predictions frontend without loading the full plugin.
local predictions_frontend = require("ask-openai.predictions.frontend")
predictions_frontend.start_predictions()

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
        local bufnr = e2e.create_test_buffer(buffer_lines)

        -- Set file type so predictions are enabled (not in ignore list)
        vim.bo.filetype = "python"
        e2e.set_cursor(2, 4) -- cursor after 4 spaces on line 2

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
        local current_prediction = e2e.wait_for_prediction(predictions_frontend, 30000)

        -- * Verify: prediction was created and has content
        assert.is_not_nil(
            current_prediction,
            "Prediction did not complete within timeout period"
        )

        -- * Assert: prediction should have accumulated text
        assert.is_true(
            #current_prediction.prediction > 0,
            "Prediction should contain text. Got empty prediction."
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

        -- Retrieve all extmarks from the buffer, including virtual text and virtual lines.
        -- The Neovim API requires the `details` option to be set to obtain `virt_text`
        -- and `virt_lines` fields. Using `{ details = true }` returns all available
        -- details for each extmark.
        local all_ns = -1
        local prediction_extmarks = vim.api.nvim_buf_get_extmarks(
            current_prediction.buffer,
            all_ns,
            0,
            -1,
            { details = true }
        )
        vim.print(prediction_extmarks)

        -- * Display full buffer after prediction (prediction is shown as extmarks so you won't see it here)
        local full_buffer = e2e.get_buffer_text(bufnr)
        print("\n========== FULL BUFFER AFTER PREDICTION ==========")
        print(full_buffer)
        print("==================================================\n")


        -- * Cleanup: cancel the prediction to free resources
        predictions_frontend.cancel_current_prediction()

        -- * Cleanup buffer
        e2e.delete_buffer(bufnr)
    end)
end)
