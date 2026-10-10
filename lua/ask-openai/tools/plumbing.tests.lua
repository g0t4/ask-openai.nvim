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
