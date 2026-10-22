require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require("luassert")
local TxChatMessage = require("ask-openai.agents.messages.tx")

describe("TxChatMessage:tool_completion", function()
    it("builds a tool-role message with the given tool_call_id", function()
        local msg = TxChatMessage:tool_completion("call_123", "Background process (pid 42) has completed.")
        assert.are.same("tool", msg.role)
        assert.are.same("call_123", msg.tool_call_id)
        assert.are.same("Background process (pid 42) has completed.", msg.content)
    end)
end)

require("ask-openai.helpers.test_setup").modify_package_path()
local Tx = require("ask-openai.agents.messages.tx")
local plumbing = require("ask-openai.tools.plumbing")

describe("tool image messages", function()
    local function result(output)
        return Tx:tool_result({ id = "call_image", ["function"] = { name = "run_bash" },
            call_output = { result = output, duration_ms = 42 } })
    end

    it("extracts stdout data URIs and preserves tool identity, text, and timing", function()
        local uri = "data:image/png;base64,aGVsbG8="
        local tool, image = result({ structuredContent = { stdout = "before\n" .. uri .. "\nafter", exit_code = 0 } })
        assert.equals("tool", tool.role)
        assert.equals("call_image", tool.tool_call_id)
        assert.equals(42, tool.duration_ms)
        assert.is_truthy(tool.content:find("before\n[image attached below]\nafter", 1, true))
        assert.is_nil(tool.content:find(uri, 1, true))
        assert.equals("user", image.role)
        assert.is_truthy(image.content[1].text:find("call_image", 1, true))
        assert.same({ type = "image_url", image_url = { url = uri } }, image.content[2])
    end)

    it("also extracts text content, deduplicates images, and handles native MCP images", function()
        local tool, image = result({ content = {
            { type = "text", text = "data:image/png;base64,aGVsbG8=\ndata:image/png;base64,aGVsbG8=" },
            { type = "image", data = "aGVsbG8=", mimeType = "image/png" },
            { type = "image", data = "d29ybGQ=", mimeType = "image/jpeg" },
        } })
        assert.equals("string", type(tool.content))
        assert.equals(3, #image.content)
        assert.equals("data:image/jpeg;base64,d29ybGQ=", image.content[3].image_url.url)
        local display = plumbing.content_to_display_text(image.content)
        assert.is_truthy(display:find("[ image omitted ]", 1, true))
        assert.is_nil(display:find("base64", 1, true))
    end)

    it("leaves ordinary text, paths, URLs, and non-image data untouched", function()
        local text = "hello /tmp/a.png https://example.com/a.png data:text/plain;base64,aGVsbG8="
        local tool, image = result({ content = { { type = "text", text = text } } })
        assert.equals(text, tool.content)
        assert.is_nil(image)
    end)

    it("supports image-only results and retains error text", function()
        local tool, image = result({ isError = true, content = { { type = "image", data = "aGVsbG8=" } } })
        assert.equals("ERROR", tool.content)
        assert.equals("data:image/png;base64,aGVsbG8=", image.content[2].image_url.url)
    end)

    it("rejects truncated stdout even when its prefix is valid base64", function()
        local tool, image = result({ structuredContent = {
            stdout = "data:image/jpeg;base64,aGVsbG8=", stdout_truncated = true, stdout_bytes = 244984,
        } })
        assert.is_nil(image)
        assert.is_truthy(tool.content:find("image not attached: tool output was truncated", 1, true))
        assert.is_nil(tool.content:find("base64,aGV", 1, true))
    end)

    it("rejects incomplete or incorrectly padded base64 instead of sending a bad image", function()
        for _, payload in ipairs({ "a", "aGVsbG8", "aGVsbG8===", "abcd=efgh" }) do
            local tool, image = result({ content = { { type = "text", text = "data:image/png;base64," .. payload } } })
            assert.is_nil(image, payload)
            assert.is_truthy(tool.content:find("invalid or incomplete base64", 1, true), payload)
        end
    end)
end)
