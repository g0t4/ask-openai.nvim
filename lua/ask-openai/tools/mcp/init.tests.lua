-- Stub missing devtools.inspect module required by the logger.
package.preload["devtools.inspect"] = function()
    return {
        bat_inspect = function(_) return "" end,
        jq_json = function(_, _) return "{}" end,
    }
end

local mcp = require("ask-openai.tools.mcp.init")
require("ask-openai.helpers.testing")
local describe = require("devtools.tests._describe")

-- Test the HTTP transport for MCP servers. The current implementation is
-- intentionally broken, so this test is expected to fail until the bug is
-- fixed. It starts the server (the module does this on require) and polls the
-- `tools_available` table for the `langchain_docs` tool, timing out after 2
-- seconds.
describe("mcp_http_transport", function()
    it("populates tools list within timeout", function()
        -- Wait up to 2000 ms, checking every 100 ms, for the langchain_docs
        -- tool to appear.
        local got_tool = vim.wait(2000, function()
            return mcp.tools_available["langchain_docs"] ~= nil
        end, 50)
        -- This assertion should initially fail (got_tool == false) until the
        -- HTTP transport is fixed.
        assert.is_true(got_tool)
    end)
end)
