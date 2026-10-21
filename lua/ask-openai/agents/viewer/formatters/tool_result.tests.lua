require("ask-openai.helpers.test_setup").modify_package_path()
local LinesBuilder = require("ask-openai.agents.viewer.lines_builder")
local ToolCall = require("ask-openai.agents.tools.tool_call")
local ToolCallOutput = require("ask-openai.agents.tools.tool_call_output")
local TxChatMessage = require("ask-openai.agents.messages.tx")
local formatters = require("ask-openai.agents.viewer.formatters")
local base = require("ask-openai.agents.viewer.formatters.base")

local message = { is_still_streaming = function() return false end, is_done_streaming = function() return true end }

describe("model-bound tool result rendering", function()
    it("uses the already-flattened response in every formatter", function()
        for _, tool_name in ipairs({ "run_bash", "run_xonsh", "run_in_neovim", "delegate", "speak", "other_tool" }) do
            local call = ToolCall:new({ id = "call", ["function"] = {
                name = tool_name, arguments = '{"command_line":"date"}',
            }, call_output = ToolCallOutput:new({ result = {
                structuredContent = { stdout = "line one\nline two", exit_code = 0 },
            } }) })
            call.response_message = TxChatMessage:tool_result(call)
            local expected = call.response_message.content
            -- Rendering must not inspect or re-flatten the raw output.
            call.call_output.result = { structuredContent = { stdout = "WRONG RAW OUTPUT" } }
            local lines = LinesBuilder:new()
            formatters.get_formatter(tool_name)(lines, call, message)
            local rendered = table.concat(lines.turn_lines, "\n")
            assert.is_truthy(rendered:find(expected, 1, true), tool_name .. ": " .. rendered)
            assert.is_nil(rendered:find("WRONG RAW OUTPUT", 1, true))
        end
    end)

    it("preserves flattened errors and omits image payloads", function()
        local lines = LinesBuilder:new()
        base.render_tool_result(lines, { response_message = { content = {
            { type = "text", text = "ERROR\n\nfailed" },
            { type = "image_url", image_url = { url = "data:image/png;base64,PRIVATE" } },
        } } })
        assert.equals("ERROR\n\nfailed\n[ image omitted ]", table.concat(lines.turn_lines, "\n"))
    end)

    it("renders nothing before the response message is built", function()
        local lines = LinesBuilder:new()
        base.render_tool_result(lines, {})
        assert.same({}, lines.turn_lines)
    end)
end)
