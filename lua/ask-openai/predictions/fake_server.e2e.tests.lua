require("ask-openai.helpers.test_setup").modify_package_path()
local config = require("ask-openai.config")

-- * Load shared E2E test utilities
local e2e = require("ask-openai.helpers.test_e2e")

-- * Load the predictions fake model server (no real backend needed!)
local fake = require("ask-openai.predictions.fake_model_server")

-- * Register only the predictions frontend without loading the full plugin.
local predictions_frontend = require("ask-openai.predictions.frontend")
predictions_frontend.start_predictions()

local describe = require("devtools.tests.describe")
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

describe("E2E - predictions with fake backend (rewrite-style)", function()
    -- * Setup: make sure we always start from a clean, deterministic state.
    --   The fake server replaces `curl.spawn`, so no real llama-server is required.
    before_each(function()
        fake.uninstall()
        fake.reset()
        fake.clear_scripts()
        fake.set_async_delivery(true)
        fake.set_chunk_delay_ms(5)

        -- * use the configured FIM model so the fake server's content_chunk SSE
        --   flows through the predictions frontend's chat-completions parser.
        --   GPTOSS is the default and uses v1_chat_completions.
        local fim_model = config.get_fim_model()
        fake.set_model_name(fim_model)

        fake.install()
    end)

    after_each(function()
        fake.uninstall()
        -- give any pending vim.schedule callbacks a chance to run before teardown
        vim.wait(100)
    end)

    it("accept full prediction (rewrite-style) and moves cursor to end", function()
        -- * Setup: create a buffer with code and position cursor
        local initial_buffer_lines = {
            "def multiply(x, y):",
            "    return x * y",
            "",
            "def add(x, y):",
            "", -- empty line: cursor at start, the model will rewrite in a body
        }
        local bufnr = e2e.create_test_buffer(initial_buffer_lines)
        print("========== INITIAL BUFFER ==========")
        print(table.concat(initial_buffer_lines, "\n"))
        print("----------------------------------------------\n")

        -- Set file type so predictions are enabled (not in ignore list)
        vim.bo.filetype = "python"
        vim.bo.buftype = "" -- empty == regular file (else test buffer is "nofile" which predictions skip)
        e2e.set_cursor_base1(5, 1) -- start of empty line (col_base1==1) on line 5

        -- * Setup: configure FIM model.
        --   We call ask_for_prediction directly (bypassing the event system), so
        --   predictions being disabled in the user's config does not block us.
        config.get_fim_model()

        -- * Script a rewrite-style completion via the fake backend.
        --   The edit-prediction contract requires the model to lead with a
        --   verbatim anchor line (a buffer line near the cursor), then the new
        --   code it wants to insert/replace. Here the model rewrites the empty
        --   `def add(x, y):` body with `return x + y`.
        fake.script("rewrite_add", {
            fake.content_chunk("def add(x, y):\n    return x + y"),
            fake.finish_chunk("stop"),
        })
        fake.use_script("rewrite_add")

        -- * Action: trigger prediction manually (bypassing event system)
        vim.cmd('startinsert') -- go into insert mode for cursor column to be correct below (end of test)
        predictions_frontend.ask_for_prediction({ bufnr = bufnr })

        -- * Wait for the prediction to complete
        local current_prediction = e2e.wait_for_prediction(bufnr, predictions_frontend, 10000)
        assert.is_not_nil(
            current_prediction,
            "Prediction did not complete within timeout period"
        )

        -- * Assert: prediction should have accumulated text
        assert.is_true(
            #current_prediction.prediction > 0,
            "Prediction should contain text. Got empty prediction."
        )

        -- * Assert: the aligned prediction produced a delta to insert
        assert.is_true(
            current_prediction.has_prediction,
            "Prediction should have aligned to a delta. Got has_prediction=false."
        )

        -- * Retrieve all extmarks from the buffer, including virtual text/lines.
        local all_ns = -1
        local all_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, all_ns, 0, -1, { details = true })

        -- * Assert on extmark details: virtual text should carry the prediction
        local all_extmark_text = text_of_extmarks(all_extmarks)
        print("========== EXTMARK TEXT ==========")
        print(all_extmark_text)
        print("----------------------------------------------\n")

        assert.is_true(
            #all_extmark_text > 0,
            "Expected extmarks to render virtual text (first_line and/or rest_of_lines)"
        )
        assert.is_true(
            all_extmark_text:find(current_prediction.first_line, 1, true) ~= nil,
            "Expected rendered extmark text to include the prediction first line. Got: '"
            .. all_extmark_text .. "'"
        )

        -- * Display full buffer after prediction (prediction is shown as extmarks)
        local buffer_before_accept = e2e.get_buffer_text(bufnr)
        assert.are_equal(table.concat(initial_buffer_lines, "\n"), buffer_before_accept)

        -- * accept prediction by pressing tab
        predictions_frontend.accept_all_invoked()

        -- * Display full buffer after prediction accepted (prediction is here)
        local buffer_after_accept = e2e.get_buffer_text(bufnr)
        print("========== BUFFER AFTER ACCEPT ==========")
        print(buffer_after_accept)
        print("----------------------------------------------\n")

        -- ** the rewritten code should now be in the buffer
        assert.is_true(
            buffer_after_accept:find("    return x + y", 1, true) ~= nil,
            "Expected accepted prediction to insert '    return x + y'. Got:\n" .. buffer_after_accept
        )

        -- ** cursor line
        local actual_cursor_line_base1, actual_cursor_col_base1 = e2e.get_cursor_base1()
        assert.are_equal(5, actual_cursor_line_base1, "cursor line mismatch")
        --
        -- ** cursor column
        --   in insert mode "i" the cursor sits one char after the last char
        --   (col_base1 = #"    return x + y" + 1 = 17); in normal mode it is 16.
        assert.are_equal(17, actual_cursor_col_base1, "cursor column mismatch")

        -- * cleanup
        predictions_frontend.cancel_current_prediction(bufnr)
        -- * give the scheduled clear_extmarks a chance to run before deleting,
        --   otherwise it fires on an already-deleted (invalid) buffer.
        vim.wait(50)
        e2e.delete_buffer(bufnr)
    end)

    it("accept a rewrite that replaces existing lines", function()
        -- * Setup: buffer where the model rewrites an existing function body.
        --   The completion leads with a verbatim anchor, then new lines, then
        --   echoes one unchanged context line after the change (the trailing
        --   echo is what makes edit_alignment treat this as a replacement).
        local initial_buffer_lines = {
            "def multiply(x, y):",
            "    return x * y",
            "",
            "def add(x, y):",
            "    result = x + y",
            "    return result",
            "",
        }
        local bufnr = e2e.create_test_buffer(initial_buffer_lines)
        vim.bo.filetype = "python"
        vim.bo.buftype = ""
        e2e.set_cursor_base1(5, 1) -- cursor at start of "    result = x + y"

        fake.script("rewrite_replace", {
            fake.content_chunk(
                "def add(x, y):\n    sum_value = x + y\n    return sum_value\n    return result"
            ),
            fake.finish_chunk("stop"),
        })
        fake.use_script("rewrite_replace")

        vim.cmd('startinsert')
        predictions_frontend.ask_for_prediction({ bufnr = bufnr })

        local current_prediction = e2e.wait_for_prediction(bufnr, predictions_frontend, 10000)
        assert.is_not_nil(current_prediction, "Prediction did not complete within timeout period")

        -- * Assert: the completion aligned to a replacement span (not a pure insert)
        assert.is_not_nil(
            current_prediction.replace_start_line_base0,
            "Expected a replacement span (replace_start_line_base0). Got nil (pure insert)."
        )
        assert.is_not_nil(
            current_prediction.replace_end_line_base0,
            "Expected a replacement span (replace_end_line_base0). Got nil (pure insert)."
        )

        -- * accept the rewrite
        predictions_frontend.accept_all_invoked()

        local buffer_after_accept = e2e.get_buffer_text(bufnr)
        print("========== BUFFER AFTER REPLACE ACCEPT ==========")
        print(buffer_after_accept)
        print("----------------------------------------------\n")

        -- ** the rewritten body replaced the original lines
        assert.is_true(
            buffer_after_accept:find("    sum_value = x + y", 1, true) ~= nil,
            "Expected replaced text '    sum_value = x + y'. Got:\n" .. buffer_after_accept
        )
        assert.is_true(
            buffer_after_accept:find("    return sum_value", 1, true) ~= nil,
            "Expected replaced text '    return sum_value'. Got:\n" .. buffer_after_accept
        )
        assert.is_true(
            buffer_after_accept:find("    return result", 1, true) ~= nil,
            "Expected echoed context '    return result' to be preserved. Got:\n" .. buffer_after_accept
        )
        assert.is_false(
            buffer_after_accept:find("    result = x + y", 1, true) ~= nil,
            "Expected replaced line '    result = x + y' to be gone. Got:\n" .. buffer_after_accept
        )

        -- ** cursor should be on the last inserted line, after it
        local actual_cursor_line_base1, actual_cursor_col_base1 = e2e.get_cursor_base1()
        assert.are_equal(6, actual_cursor_line_base1, "cursor line mismatch")
        assert.are_equal(21, actual_cursor_col_base1, "cursor column mismatch")

        predictions_frontend.cancel_current_prediction(bufnr)
        vim.wait(50)
        e2e.delete_buffer(bufnr)
    end)

    it("shows reasoning as thinking extmarks before any content", function()
        -- * Setup: a model that streams reasoning/thinking tokens first.
        --   While only reasoning has arrived (no content), the frontend must
        --   show the "still thinking" message plus the reasoning lines.
        local initial_buffer_lines = {
            "def add(x, y):",
            "",
            "",
        }
        local bufnr = e2e.create_test_buffer(initial_buffer_lines)
        vim.bo.filetype = "python"
        vim.bo.buftype = ""
        e2e.set_cursor_base1(2, 1)

        -- * NOTE: no finish_chunk here. Sending a finish chunk with an empty
        --   prediction would cause finalize_prediction to clear the extmarks.
        fake.script("thinking", {
            fake.reasoning_chunk("Let me think about the best implementation...", "assistant"),
            fake.reasoning_chunk("I will use a clear variable name."),
        })
        fake.use_script("thinking")

        vim.cmd('startinsert')
        predictions_frontend.ask_for_prediction({ bufnr = bufnr })

        -- * wait for the reasoning to be reflected on the prediction object
        local reasoning_seen = e2e.wait_for(function()
            local pred = predictions_frontend._get_current_prediction(bufnr)
            return pred ~= nil and pred.has_reasoning
        end, 5000, 50)
        assert.is_true(reasoning_seen, "Reasoning was not seen within timeout period")

        local current_prediction = predictions_frontend._get_current_prediction(bufnr)
        assert.is_true(current_prediction.has_reasoning, "Prediction should have reasoning")

        -- * the reasoning text should be rendered via extmark virt_lines
        local all_ns = -1
        local all_extmarks = vim.api.nvim_buf_get_extmarks(bufnr, all_ns, 0, -1, { details = true })
        local all_extmark_text = text_of_extmarks(all_extmarks)
        print("========== REASONING EXTMARK TEXT ==========")
        print(all_extmark_text)
        print("----------------------------------------------\n")

        assert.is_true(
            all_extmark_text:find("Let me think about the best implementation", 1, true) ~= nil,
            "Expected reasoning text in extmarks. Got:\n" .. all_extmark_text
        )

        predictions_frontend.cancel_current_prediction(bufnr)
        vim.wait(50)
        e2e.delete_buffer(bufnr)
    end)
end)
