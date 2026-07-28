require("ask-openai.helpers.test_setup").modify_package_path()

-- * Register only the AskAgent user command without loading the full plugin.
--   The full init loads telescope (via rag) which isn't available in headless mode.
local frontend = require("ask-openai.agents.frontend")
frontend.setup()

local describe = require("devtools.tests.define.describe")
local should = require("devtools.tests.should")
local assert = require("luassert")

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

--- Extract the assistant's response text from the chat window buffer.
--- Looks for lines that are not role headers, system messages, or blank lines.
--- @param bufnr number The buffer number of the chat window
--- @return string[] lines Array of content lines from the assistant response
local function extract_assistant_response(bufnr)
    local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local response_lines = {}
    local in_assistant_section = false

    for _, line in ipairs(all_lines) do
        -- Detect assistant role headers
        if line:match("^assistant$") or line:match("^assistant%s*$") then
            in_assistant_section = true
            goto continue
        end

        -- Detect user role headers (ends assistant section)
        if line:match("^user$") or line:match("^user%s*$") then
            in_assistant_section = false
            goto continue
        end

        -- Detect system prompt markers
        if line:match("^%-%-%- New Trace Started %-%-%-$") or line:match("^system$") then
            in_assistant_section = false
            goto continue
        end

        -- Skip blank lines at the start of assistant section
        if in_assistant_section and line:match("^%s*$") then
            if #response_lines > 0 then
                table.insert(response_lines, "")
            end
            goto continue
        end

        if in_assistant_section and not line:match("^%s*$") then
            table.insert(response_lines, line)
        end

        ::continue::
    end

    return response_lines
end

describe("E2E - AskAgent /tools with date question", function()
    it("should respond to 'what date is it' and display the answer in chat window", function()
        -- * Setup: ensure plugin is loaded and configured for agents mode
        local api = require("ask-openai.api")
        local frontend = require("ask-openai.agents.frontend")

        -- Set a model for testing (use whatever is available)
        api.set_agents_model(api.get_agents_model() or "qwen")

        -- * Action: invoke the AskAgent command with tools and a date question
        local user_prompt = "what date is it"
        vim.cmd(string.format("AskAgent /tools %s", user_prompt))

        -- * Wait for the agent to finish processing
        -- The agent finishes when the chat window stops spinning (agent_is_running becomes false)
        local chat_window_ready = wait_for(function()
            if not frontend.chat_window then
                return false
            end
            return not frontend.chat_window._agent_is_running
        end, 120000, 500) -- 120 second timeout, poll every 500ms

        assert.is_true(chat_window_ready, "Agent did not finish within timeout period")

        -- * Verify: chat window exists and has content
        assert.is_not_nil(frontend.chat_window, "Chat window was not created")
        assert.is_true(
            vim.api.nvim_win_is_valid(frontend.chat_window.win_id),
            "Chat window is not valid"
        )

        local bufnr = frontend.chat_window.buffer_number
        local line_count = vim.api.nvim_buf_line_count(bufnr)
        assert.is_true(line_count > 0, "Chat window buffer is empty")

        -- * Extract and display the assistant's response
        local assistant_lines = extract_assistant_response(bufnr)
        local full_response = table.concat(assistant_lines, "\n")

        print("\n========== ASSISTANT RESPONSE ==========")
        print(full_response)
        print("========================================\n")

        -- * Assert: response should contain date-related content
        -- Note: string.match returns the matched string (truthy) or nil (falsy),
        --   so we use assert.is_not_nil to check truthiness
        local has_date_keyword = full_response:lower():match("date")
            or full_response:lower():match("today")
        assert.is_not_nil(
            has_date_keyword,
            "Response should contain 'date' or 'today'. Got: " .. full_response
        )

        -- Lua patterns don't support {4} quantifiers, so spell out the digits
        local has_iso_date = full_response:match("%d%d%d%d%-?%d%d%-?%d%d")
        assert.is_not_nil(
            has_iso_date,
            "Response should contain a date string (YYYY-MM-DD). Got: " .. full_response
        )

        -- * Assert: response should not be empty or just tool call artifacts
        local has_meaningful_content = #full_response > 10
        assert.is_true(
            has_meaningful_content,
            "Response should have meaningful content (not just tool call formatting)"
        )
    end)
end)
