require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require "luassert"
local describe = require("devtools.tests.describe")

local plumbing = require("ask-openai.tools.plumbing")

describe("extract_image_data_urls", function()
    it("returns empty list when there are no image blocks", function()
        local result = {
            content = {
                { type = "text", text = "Screenshot saved to: /tmp/x.png" },
            },
        }
        assert.are.same({}, plumbing.extract_image_data_urls(result))
    end)

    it("builds a data URL for each image content block", function()
        local result = {
            content = {
                { type = "text", text = "Screenshot saved to: /tmp/x.png" },
                { type = "image", data = "aGVsbG8=", mimeType = "image/png" },
                { type = "image", data = "d29ybGQ=", mimeType = "image/jpeg" },
            },
        }
        local urls = plumbing.extract_image_data_urls(result)
        assert.are.same({
            "data:image/png;base64,aGVsbG8=",
            "data:image/jpeg;base64,d29ybGQ=",
        }, urls)
    end)

    it("defaults mimeType to image/png when absent", function()
        local result = {
            content = { { type = "image", data = "aGVsbG8=" } },
        }
        assert.are.same({ "data:image/png;base64,aGVsbG8=" }, plumbing.extract_image_data_urls(result))
    end)

    it("handles non-table results gracefully", function()
        assert.are.same({}, plumbing.extract_image_data_urls(nil))
        assert.are.same({}, plumbing.extract_image_data_urls("some text"))
    end)
end)

describe("flatten_tool_result_to_text", function()
    it("flattens structuredContent into labeled text", function()
        local result = {
            isError = false,
            content = {},
            structuredContent = {
                exit_code = 0,
                stdout = "hello world\n",
                stderr = "",
                duration_ms = 42,
                timed_out = false,
            },
        }
        local flat = plumbing.flatten_tool_result_to_text(result)
        assert.matches("exit_code: 0", flat)
        assert.matches("stdout:\nhello world", flat)
        assert.matches("duration_ms: 42", flat)
        -- empty stderr should be skipped
        assert.is_nil(string.find(flat, "stderr:", 1, true))
    end)

    it("prepends ERROR for isError results", function()
        local result = {
            isError = true,
            content = {},
            structuredContent = {
                exit_code = 7,
                stderr = "bad\n",
            },
        }
        local flat = plumbing.flatten_tool_result_to_text(result)
        assert.matches("^ERROR", flat)
        assert.matches("exit_code: 7", flat)
        assert.matches("stderr:\nbad", flat)
    end)

    it("falls back to content blocks when no structuredContent", function()
        local result = {
            content = {
                { type = "text", text = "hello", name = "STDOUT" },
                { type = "text", text = "0", name = "EXIT_CODE" },
            },
        }
        local flat = plumbing.flatten_tool_result_to_text(result)
        assert.matches("STDOUT:\nhello", flat)
        assert.matches("EXIT_CODE: 0", flat)
    end)

    it("handles nil or non-table results gracefully", function()
        assert.are.same("nil", plumbing.flatten_tool_result_to_text(nil))
        assert.are.same("some text", plumbing.flatten_tool_result_to_text("some text"))
    end)
end)
