require("ask-openai.helpers.test_setup").modify_package_path()
local config = require("ask-openai.config")
local screen = require("devtools.tests.screen")

-- * Load shared E2E test utilities
local e2e = require("ask-openai.helpers.test_e2e")

-- * Register only the predictions frontend without loading the full plugin.
local predictions_frontend = require("ask-openai.predictions.frontend")
predictions_frontend.start_predictions()

local describe = require("devtools.tests.define.describe")
local should = require("devtools.tests.should")
local assert = require("luassert")

-- * Calculator helpers

-- Reference calculator (formatting guide for the function below): gather all
-- text rendered via extmarks (virt_text + virt_lines) in buffer order.
---@param extmarks table[]
---@return string rendered_text
local function calculate_rendered_extmark_text(extmarks)
    local chunks = {}
    for _, extmark in ipairs(extmarks) do
        local details = extmark[4] or {}
        if details.virt_lines then
            for _, line_parts in ipairs(details.virt_lines) do
                for _, part in ipairs(line_parts) do
                    table.insert(chunks, part[1])
                end
            end
        end
        if details.virt_text then
            for _, part in ipairs(details.virt_text) do
                table.insert(chunks, part[1])
            end
        end
    end
    return table.concat(chunks, "\n")
end

-- New calculator: expected cursor position after accepting the prediction
-- (cursor lands at the end of the last inserted line).
---@param buffer_text string
---@return number line_base1
---@return number col_base1
local function calculate_expected_cursor_after_accept(buffer_text)
    local lines = vim.split(buffer_text, "\n")
    local last_line = lines[#lines]
    return #lines, #last_line + 1
end

describe("E2E - FIM predictions", function()
    it("should get a prediction when triggered from a code buffer", function()
        -- * Setup: create a buffer with code and position cursor
        local buffer_lines = {
            "def add(x, y):",
            "", -- empty line: cursor at start, expecting "return x + y"
        }
        local bufnr = e2e.create_test_buffer(buffer_lines)

        -- Set file type so predictions are enabled (not in ignore list)
        vim.bo.filetype = "python"
        -- print("buftype", vim.bo.buftype)
        vim.bo.buftype = "" -- empty == regular file (else test buffer is "nofile" which my predictions skip)
        e2e.set_cursor_base1(2, 1) -- start of empty line (col_base1==1) on line 2

        -- * Setup: configure FIM model
        -- Guard: FIM predictions must be enabled (the request path short-circuits when disabled,
        --   which would otherwise show up as a confusing 30s timeout instead of the real cause).
        assert.are_equal(
            true,
            config.are_predictions_enabled(),
            "FIM/predictions are DISABLED. Enable them (e.g. :AskEnablePredictions or :AskTogglePredictions) before running this e2e FIM test."
        )
        local fim_model = config.get_fim_model() or "qwen"
        config.set_fim_model(fim_model)

        print("\n========== TRIGGERING FIM PREDICTION ==========")
        print("  Buffer lines: " .. table.concat(buffer_lines, ", "))
        print("  FIM model: " .. fim_model)
        print("==============================================\n")
        -- screen.dump_bounded("before FIM")

        -- * Action: trigger prediction manually (bypassing event system)
        predictions_frontend.ask_for_prediction({ bufnr = bufnr })

        -- * Wait for the prediction to complete
        local current_prediction = e2e.wait_for_prediction(bufnr, predictions_frontend, 30000)

        -- screen.dump_bounded("after FIM")

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
            bufnr,
            all_ns,
            0,
            -1,
            { details = true }
        )
        vim.print(prediction_extmarks)
        -- * assert on extmarks
        assert.is_true(#prediction_extmarks > 0, "Expected extmarks to be present after prediction")


        -- * Assert on extmark details: virtual text/lines should carry the prediction text
        local rendered_text = calculate_rendered_extmark_text(prediction_extmarks)
        print("\n========== RENDERED EXTMARK TEXT ==========")
        print(rendered_text)
        print("==========================================\n")

        -- * Assert: the rendered virtual text matches the prediction shown (duplicate prefix stripped)
        assert.is_true(
            #rendered_text > 0,
            "Expected extmarks to render virtual text (first_line and/or rest_of_lines)"
        )
        assert.is_true(
            rendered_text:find(current_prediction.first_line, 1, true) ~= nil,
            "Expected rendered extmark text to include the prediction first line. Got: '"
            .. rendered_text .. "'"
        )

        -- * Display full buffer after prediction (prediction is shown as extmarks so you won't see it here)
        local full_buffer_before_accept = e2e.get_buffer_text(bufnr)
        print("\n========== FULL BUFFER AFTER PREDICTION (no extmarks) ==========")
        print(full_buffer_before_accept)
        print("==================================================\n")

        -- * accept prediction by pressing tab
        predictions_frontend.accept_all_invoked()

        -- * Display full buffer after prediction accepted (prediction is here)
        local full_buffer_after_accept = e2e.get_buffer_text(bufnr)
        print("\n========== FULL BUFFER AFTER ACCEPT ==========")
        print(full_buffer_after_accept)
        print("==================================================\n")

        screen.dump_bounded("after accept")

        -- * Assert: cursor moved to the end of the accepted prediction (soft check -
        --   a wrong model response may still be acceptable, so warn instead of fail)
        local expected_cursor_line_base1, expected_cursor_col_base1 = calculate_expected_cursor_after_accept(
            full_buffer_after_accept
        )
        local actual_cursor_line_base1, actual_cursor_col_base1 = e2e.get_cursor_base1()
        print("\n========== CURSOR AFTER ACCEPT ==========")
        print("  Expected: line " .. expected_cursor_line_base1 .. ", col " .. expected_cursor_col_base1)
        print("  Actual:   line " .. actual_cursor_line_base1 .. ", col " .. actual_cursor_col_base1)
        print("==========================================\n")
        if actual_cursor_line_base1 ~= expected_cursor_line_base1
            or actual_cursor_col_base1 ~= expected_cursor_col_base1
        then
            print("NOTE: cursor did not land at the expected spot.")
            print("      The prediction might still be ok - manually review the buffer above.")
        end

        -- * TODO run other tests w/ accept_line_invoked and accept_word_invoked
        --  and verify how they behave!!!


        -- * Cleanup: cancel the prediction to free resources
        predictions_frontend.cancel_current_prediction(bufnr)

        -- * Cleanup buffer
        e2e.delete_buffer(bufnr)
    end)
end)
