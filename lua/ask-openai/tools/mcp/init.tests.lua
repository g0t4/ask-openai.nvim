require("ask-openai.helpers.testing")
local mcp = require("ask-openai.tools.mcp")
local describe = require("devtools.tests._describe")

describe("mcp_http_transport", function()
    it("populates tools list within timeout", function()
        local got_tool = vim.wait(2000, function()
            -- vim.print(mcp.tools_available)
            return mcp.tools_available["search_docs_by_lang_chain"] ~= nil
        end, 50)
        assert.is_true(got_tool)
    end)
end)
