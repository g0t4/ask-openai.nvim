require("ask-openai.helpers.test_setup").modify_package_path()
local config = require("ask-openai.config")

-- * Register only the AskAgent user command without loading the full plugin.
--   The full init loads telescope (via rag) which isn't available in headless mode.
local frontend = require("ask-openai.agents.frontend")
frontend.setup()

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

-- * Wait for MCP servers to initialize
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

-- * Debug: check what tools are available
print("\n========== MCP TOOLS AVAILABLE ==========")
for name, tool in pairs(mcp_tools.tools_available or {}) do
    print("  - " .. name)
end
print("========================================\n")

-- * Assert: run_process tool must be available for this test
local has_run_process_tool = mcp_tools.tools_available["run_process"] ~= nil
assert.is_true(
    has_run_process_tool,
    "MCP tools must include 'run_process' for this test. Available tools:\n"
    .. table.concat(vim.tbl_keys(mcp_tools.tools_available or {}), ", ")
)

local describe = require("devtools.tests.define.describe")
local should = require("devtools.tests.should")
local assert = require("luassert")

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
    it("should use run_process tool to get date and show green checkmark", function()
        -- * Setup: ensure plugin is loaded and configured for agents mode
        local api = require("ask-openai.api")
        local frontend = require("ask-openai.agents.frontend")

        -- Set a model for testing (use whatever is available)
        config.set_agents_model(config.get_agents_model() or "qwen")

        -- * Action: invoke the AskAgent command with tools and a date question
        --   Prompt explicitly asks to use the run_process tool
        local user_prompt = "use the run_process tool to run 'date' and show me today's date"
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

        -- * Extract and display the full buffer content for debugging
        local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local full_buffer = table.concat(all_lines, "\n")

        print("\n========== FULL BUFFER CONTENT ==========")
        print(full_buffer)
        print("========================================\n")

        -- * Assert: check for green checkmark (✅) indicating successful tool execution
        -- The run_process formatter adds "✅ " prefix to successful tool calls
        local has_green_checkmark = full_buffer:match("✅")
        assert.is_not_nil(
            has_green_checkmark,
            "Response should contain green checkmark (✅) for successful tool execution. Full buffer:\n" .. full_buffer
        )

        -- * Assert: response should contain date-related content from tool output
        local has_date_keyword = full_buffer:lower():match("date")
            or full_buffer:lower():match("today")
        assert.is_not_nil(
            has_date_keyword,
            "Response should contain 'date' or 'today'. Full buffer:\n" .. full_buffer
        )

        -- * Assert: response should contain a date string (any format)
        -- Accept formats like: "2026-07-28", "Tue Jul 28 01:14:41 CDT 2026", "July 28, 2026", etc.
        local has_date_string = full_buffer:match("%d%d%d%d")
            or full_buffer:match("Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec")
        assert.is_not_nil(
            has_date_string,
            "Response should contain a date string. Full buffer:\n" .. full_buffer
        )

        -- * Assert: response should contain tool-related content
        local has_tool_reference = full_buffer:match("run_process")
            or full_buffer:match("date")
        assert.is_not_nil(
            has_tool_reference,
            "Response should reference the run_process tool or date. Full buffer:\n" .. full_buffer
        )
    end)
end)
