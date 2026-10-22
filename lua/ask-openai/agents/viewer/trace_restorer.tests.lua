require("ask-openai.helpers.test_setup").modify_package_path()

describe("restoring flattened tool messages", function()
    local originals, buffer, frontend, restorer, original_load
    before_each(function()
        originals = {}
        local function replace(name, module)
            originals[name] = { value = package.loaded[name] }
            package.loaded[name] = module
        end
        buffer = vim.api.nvim_create_buf(false, true)
        frontend = {
            ensure_chat_window_is_open = function() end,
            chat_window = {
                clear = function() end,
                buffer_number = buffer,
                buffer = { folds = {}, get_line_count = function() return vim.api.nvim_buf_line_count(buffer) end },
            },
        }
        replace("ask-openai.agents.frontend", frontend)
        replace("ask-openai.config", { get_agents_model = function() return "test" end,
            get_base_url = function() return "http://test" end })
        replace("ask-openai.tools.router", { openai_tools = function() return {} end })
        replace("ask-openai.agents.trace", { new = function() return {} end })
        replace("ask-openai.agents.viewer.trace_restorer", nil)
        restorer = require("ask-openai.agents.viewer.trace_restorer")
        original_load = restorer.load_trace
    end)
    after_each(function()
        restorer.load_trace = original_load
        for name, original in pairs(originals) do package.loaded[name] = original.value end
        vim.api.nvim_buf_delete(buffer, { force = true })
    end)

    it("renders image messages without payloads and retains image inputs for follow-up", function()
        local content = {
            { type = "text", text = "Images returned by run_bash." },
            { type = "image_url", image_url = { url = "data:image/png;base64,PRIVATE" } },
        }
        restorer.load_trace = function()
            return { request_body = { messages = {
                { role = "user", content = content },
                { role = "assistant", content = "I can see the image." },
            } } }
        end
        assert.is_true(restorer.restore_session("unused"))
        assert.is_true(vim.wait(1000, function() return frontend.trace ~= nil end, 10))
        local rendered = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
        assert.is_truthy(rendered:find("[ image omitted ]", 1, true), rendered)
        assert.is_nil(rendered:find("PRIVATE", 1, true))
        assert.same(content, frontend.trace.messages[1].content)
    end)

    it("renders saved output verbatim and retains it for follow-up", function()
        local text = 'STDOUT: plain output\nJSON looking text: {"keep":"verbatim"}'
        local tool_message = { role = "tool", tool_call_id = "call", content = text, duration_ms = 42 }
        restorer.load_trace = function()
            return { request_body = { messages = {
                { role = "assistant", content = "", tool_calls = { { id = "call", type = "function",
                    ["function"] = { name = "run_bash", arguments = '{"command_line":"date"}' } } } },
                tool_message,
            } } }
        end
        assert.is_true(restorer.restore_session("unused"))
        assert.is_true(vim.wait(1000, function() return frontend.trace ~= nil end, 10))
        local rendered = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
        assert.is_truthy(rendered:find(text, 1, true), rendered)
        assert.is_nil(rendered:find("Formatter error", 1, true))
        assert.equals(text, frontend.trace.messages[2].content)
        assert.equals(42, frontend.trace.messages[2].duration_ms)
    end)
end)
