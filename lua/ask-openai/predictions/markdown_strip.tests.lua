-- testing modules:
require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require 'luassert'
local buffers = require('devtools.tests.buffers')
local markdown_strip = require("ask-openai.predictions.markdown_strip")
local Prediction = require("ask-openai.predictions.prediction")

describe("markdown_strip.strip_leading_fence", function()
    it("strips a fence with a language", function()
        assert.equal("return x", markdown_strip.strip_leading_fence("```lua\nreturn x"))
    end)

    it("strips a bare fence (no language)", function()
        assert.equal("return x", markdown_strip.strip_leading_fence("```\nreturn x"))
    end)

    it("strips an empty fence plus newline", function()
        assert.equal("", markdown_strip.strip_leading_fence("```lua\n"))
    end)

    it("does NOT strip a partial fence without a newline (streaming safe)", function()
        assert.equal("```lua", markdown_strip.strip_leading_fence("```lua"))
    end)

    it("does NOT strip when the fence line has trailing content on the same line", function()
        assert.equal("```lua is great\ncode", markdown_strip.strip_leading_fence("```lua is great\ncode"))
    end)

    it("strips the fence even when there are blank lines before content", function()
        assert.equal("\n\ncode", markdown_strip.strip_leading_fence("```lua\n\n\ncode"))
    end)
end)

describe("markdown_strip.strip_trailing_fence", function()
    it("strips a trailing fence at the very end", function()
        assert.equal("code", markdown_strip.strip_trailing_fence("code\n```"))
    end)

    it("strips a trailing fence followed by a newline", function()
        assert.equal("code\n", markdown_strip.strip_trailing_fence("code\n```\n"))
    end)

    it("strips when the fence is the entire text", function()
        assert.equal("", markdown_strip.strip_trailing_fence("```"))
    end)

    it("does NOT strip a fence that is not at the end", function()
        assert.equal("code\n```\nmore", markdown_strip.strip_trailing_fence("code\n```\nmore"))
    end)
end)

describe("markdown_strip.strip_inline_backticks", function()
    it("strips a single leading/trailing backtick wrapper", function()
        assert.equal("code", markdown_strip.strip_inline_backticks("`code`"))
    end)

    it("strips an inline wrapper followed by a trailing newline", function()
        assert.equal("code", markdown_strip.strip_inline_backticks("`code`\n"))
    end)

    it("does NOT strip a partial inline wrapper (no trailing backtick yet)", function()
        assert.equal("`code", markdown_strip.strip_inline_backticks("`code"))
    end)

    it("does NOT strip a triple backtick (that is a fence, not inline)", function()
        assert.equal("```code```", markdown_strip.strip_inline_backticks("```code```"))
    end)

    it("does NOT strip a lone single backtick", function()
        assert.equal("`", markdown_strip.strip_inline_backticks("`"))
    end)
end)

describe("markdown_strip.strip", function()
    it("strips leading + trailing fences", function()
        assert.equal("code", markdown_strip.strip("```lua\ncode\n```"))
    end)

    it("strips inline backticks", function()
        assert.equal("code", markdown_strip.strip("`code`"))
    end)

    it("strips inline backticks followed by a trailing newline", function()
        assert.equal("code", markdown_strip.strip("`code`\n"))
    end)

    it("leaves plain code untouched", function()
        assert.equal("local x = 1", markdown_strip.strip("local x = 1"))
    end)
end)

describe("Prediction:fim_fixes markdown fence stripping", function()
    local function new_prediction_with_content(lines, content, filetype)
        local bufnr = buffers.new_buffer_with_lines(lines)
        -- cursor on an empty line so the duplicate-prefix logic is a no-op
        vim.api.nvim_win_set_cursor(0, { #lines, 0 })
        if filetype then
            vim.bo[bufnr].filetype = filetype
        end
        local prediction = Prediction.new({ bufnr = bufnr })
        prediction.prediction = content
        prediction:fim_fixes()
        return prediction
    end

    it("strips a leading ```lang fence from the shown first line", function()
        local prediction = new_prediction_with_content({ "def foo():", "" }, "```lua\ndef foo():\nreturn x")
        assert.is_true(prediction.has_prediction)
        assert.equal("return x", prediction.first_line)
        assert.equal(0, #prediction.rest_of_lines)
    end)

    it("strips a trailing ``` fence from the shown lines", function()
        local prediction = new_prediction_with_content({ "def foo():", "" }, "def foo():\nreturn x\n```")
        assert.is_true(prediction.has_prediction)
        assert.equal("return x", prediction.first_line)
        assert.equal(0, #prediction.rest_of_lines)
    end)

    it("strips both fences and keeps multiline content", function()
        local prediction = new_prediction_with_content({ "def foo():", "" }, "```lua\ndef foo():\nreturn x\nreturn y\n```")
        assert.is_true(prediction.has_prediction)
        assert.equal("return x", prediction.first_line)
        assert.are_same({ "return y" }, prediction.rest_of_lines)
    end)

    it("strips inline single backticks", function()
        local prediction = new_prediction_with_content({ "def foo():", "" }, "`def foo():\nreturn x`")
        assert.is_true(prediction.has_prediction)
        assert.equal("return x", prediction.first_line)
    end)

    it("strips inline single backticks followed by a trailing newline", function()
        local prediction = new_prediction_with_content({ "def foo():", "" }, "`def foo():\nreturn x`\n")
        assert.is_true(prediction.has_prediction)
        assert.equal("return x", prediction.first_line)
    end)

    it("is streaming-safe: partial fence without an anchor shows no prediction yet", function()
        local prediction = new_prediction_with_content({ "def foo():", "" }, "```lua")
        assert.is_false(prediction.has_prediction)
    end)

    it("is streaming-safe: empty fence has no prediction yet", function()
        local prediction = new_prediction_with_content({ "def foo():", "" }, "```lua\n")
        assert.is_false(prediction.has_prediction)
    end)

    it("does NOT strip fences in a markdown buffer", function()
        local prediction = new_prediction_with_content(
            { "# Title", "" },
            "```lua\nreturn x\n```",
            "markdown"
        )
        assert.is_true(prediction.has_prediction)
        assert.equal("```lua", prediction.first_line)
    end)
end)
