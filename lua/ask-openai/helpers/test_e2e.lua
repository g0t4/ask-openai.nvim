--- Shared E2E test utilities for ask-openai.nvim
--- Provides reusable helpers for building end-to-end tests.

local M = {}

--- Wait for a condition to become true, polling every `poll_ms` milliseconds.
--- @param predicate fun(): boolean
--- @param timeout_ms number Maximum time to wait in milliseconds
--- @param poll_ms number Time between polls in milliseconds
--- @return boolean success Whether the condition became true before timeout
function M.wait_for(predicate, timeout_ms, poll_ms)
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

--- Create a new buffer with the given lines and make it the current window's buffer.
--- @param lines string[] Lines to populate the buffer with
--- @return number bufnr The created buffer number
function M.create_test_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_win_set_buf(0, bufnr)
    return bufnr
end

--- Set the cursor position in the current window.
--- @param line_base1 number 1-indexed line number
--- @param col_base1 number 1-indexed column number
function M.set_cursor_base1(line_base1, col_base1)
    local col_base0 = col_base1 - 1
    vim.api.nvim_win_set_cursor(0, { line_base1, col_base0 })
end

--- Get all lines from a buffer as a single string.
--- @param bufnr number The buffer number
--- @return string text The full buffer contents joined with newlines
function M.get_buffer_text(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    return table.concat(lines, "\n")
end

--- Delete a buffer if it exists and is valid.
--- @param bufnr number The buffer number to delete
function M.delete_buffer(bufnr)
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end
end

--- Wait for a FIM prediction to complete and return it.
--- @param predictions_frontend PredictionsFrontend The predictions frontend module
--- @param timeout_ms number Maximum time to wait in milliseconds
--- @return table|nil prediction The completed prediction object, or nil if timed out
function M.wait_for_prediction(bufnr, predictions_frontend, timeout_ms)
    timeout_ms = timeout_ms or 30000

    local success = M.wait_for(function()
        local current = predictions_frontend._get_current_prediction(bufnr)
        if not current then
            return false
        end
        return current.prediction ~= nil and current.prediction ~= ""
    end, timeout_ms, 200)

    if success then
        return predictions_frontend._get_current_prediction(bufnr)
    end

    return nil
end

--- Wait for a rewrite response to complete.
--- Checks that the displayer exists and has accumulated chunks.
--- @param rewrite_frontend table The rewrite frontend module
--- @param timeout_ms number Maximum time to wait in milliseconds
--- @return boolean success Whether the rewrite completed
function M.wait_for_rewrite(rewrite_frontend, timeout_ms)
    timeout_ms = timeout_ms or 60000

    return M.wait_for(function()
        if not rewrite_frontend.displayer then
            return false
        end
        local response = rewrite_frontend.response
        if not response then
            return false
        end
        -- Response is done when it has accumulated content and is no longer streaming
        return response.accumulated_chunks ~= nil and response.accumulated_chunks ~= ""
    end, timeout_ms, 200)
end

--- Extract just the code portion from a rewrite response (strips markdown if present).
--- @param response table The rewrite response object
--- @return string code The cleaned code without markdown wrappers
function M.extract_code_from_rewrite(response)
    if not response or not response.accumulated_chunks then
        return ""
    end

    local text = response.accumulated_chunks
    -- Strip markdown code block wrappers if present
    text = text:gsub("^```%S*\n", ""):gsub("\n```$", "")
    return text
end

return M
