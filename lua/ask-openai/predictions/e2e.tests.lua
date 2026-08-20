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
local function text_of_extmarks(extmarks)
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

describe("E2E - FIM predictions", function()
    -- TODO! other primary scenario integration tests?
    --   do not need to test edge cases of minor things... just top level features
    --   largely the ones that require custom UI code that needs to be validated
    --   push as much  as possible into unit tests
    --   i.e. validating cursor position is best done mathematically and then we just make sure the #s get plugged in here to actually move the cursor for one case

    it("accept full prediction", function()
        -- * Setup: create a buffer with code and position cursor
        local initial_buffer_lines = {
            "def multiply(x, y):",
            "    return x * y",
            "",
            "def add(x, y):",
            "", -- empty line: cursor at start, expecting "return x + y"
        }
        local bufnr = e2e.create_test_buffer(initial_buffer_lines)
        print("========== INITIAL BUFFER ==========")
        print(table.concat(initial_buffer_lines, "\n"))
        print("----------------------------------------------\n")
        -- screen.dump_bounded("before FIM")

        -- Set file type so predictions are enabled (not in ignore list)
        vim.bo.filetype = "python"
        -- print("buftype", vim.bo.buftype)
        vim.bo.buftype = "" -- empty == regular file (else test buffer is "nofile" which my predictions skip)
        e2e.set_cursor_base1(5, 1) -- start of empty line (col_base1==1) on line 2

        -- * Setup: configure FIM model
        -- Guard: FIM predictions must be enabled (the request path short-circuits when disabled,
        --   which would otherwise show up as a confusing 30s timeout instead of the real cause).
        assert.are_equal(
            true,
            config.are_predictions_enabled(),
            "FIM/predictions are DISABLED. Enable them (e.g. :AskEnablePredictions or :AskTogglePredictions) before running this e2e FIM test."
        )
        config.get_fim_model()

        -- * Action: trigger prediction manually (bypassing event system)
        vim.cmd('startinsert') -- go into insert mode for cursor column to be correct below (end of test)
        -- print("mode:", vim.fn.mode()) -- TODO timing issue why this is still "n" here? or?
        --  and yet w/o startinsert here ... the cursor calc at end is wrong so WTF.. why is it still marked normal mode
        --  and even though still normal why does cursor col at end seem to behave as if it is insert mode?!
        --  and down there at end mode() still reports "n"
        --  vim.schedule (function () mode()end) still reports "n" too?!
        --  perhaps test scheduler issue or?
        --
        -- TODO get test to trigger on insert mode alone?
        --   would need to change test buffer type/filetype to not be ignored by my predictions_frontend
        --   and other stuff that's blocking, not sure yet (async timing most likely)
        --   ahhh yes that is why startinsert is probably not triggering here... perhaps it would if I waited and deferred assertions until after this completes!
        -- trigger manually for now:
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

        -- -- * Display the prediction for debugging
        -- print("========== PREDICTION RESULT ==========")
        -- print("  Prediction text: '" .. current_prediction.prediction .. "'")
        -- print("  Has duplicate prefix: " .. tostring(current_prediction.has_duplicate_prefix))
        -- print("  First line: '" .. (current_prediction.first_line or "(none)") .. "'")
        -- print("----------------------------------------------\n")

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
        local all_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, all_ns, 0, -1, { details = true })

        -- * Assert on extmark details: virtual text/lines should carry the prediction text
        local all_extmark_text = text_of_extmarks(all_extmarks)
        print("========== EXTMARK TEXT ==========")
        print(all_extmark_text)
        print("----------------------------------------------\n")

        -- * Assert: the rendered virtual text matches the prediction shown (duplicate prefix stripped)
        assert.is_true(
            #all_extmark_text > 0,
            "Expected extmarks to render virtual text (first_line and/or rest_of_lines)"
        )
        assert.is_true(
            all_extmark_text:find(current_prediction.first_line, 1, true) ~= nil,
            "Expected rendered extmark text to include the prediction first line. Got: '"
            .. all_extmark_text .. "'"
        )

        -- * Display full buffer after prediction (prediction is shown as extmarks so you won't see it here)
        local buffer_before_accept = e2e.get_buffer_text(bufnr)
        assert.are_equal(table.concat(initial_buffer_lines, "\n"), buffer_before_accept)

        -- * accept prediction by pressing tab
        predictions_frontend.accept_all_invoked()

        -- * Display full buffer after prediction accepted (prediction is here)
        local buffer_after_accept = e2e.get_buffer_text(bufnr)
        print("========== BUFFER AFTER ACCEPT ==========")
        print(buffer_after_accept)
        print("----------------------------------------------\n")

        -- screen.dump_bounded("after accept")

        -- ** cursor line
        local actual_cursor_line_base1, actual_cursor_col_base1 = e2e.get_cursor_base1()
        assert.are_equal(5, actual_cursor_line_base1, "cursor line mismatch")
        --
        -- ** cursor column
        assert.are_equal(17, actual_cursor_col_base1, "cursor column mismatch")
        -- FYI if in insert mode "i" then add one to cursor column (char after last char) and is thus 17 for insert mode
        -- in normal mode it is last char column (not char after) hence why it is 16 then for normal mode

        -- * cleanup
        predictions_frontend.cancel_current_prediction(bufnr)
        e2e.delete_buffer(bufnr)
    end)
end)
