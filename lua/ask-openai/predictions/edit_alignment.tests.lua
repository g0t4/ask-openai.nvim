-- testing modules:
require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require 'luassert'
local edit_alignment = require("ask-openai.predictions.edit_alignment")

local function buffer_lines()
    return {
        "def foo():",
        "    result = x + y",
        "    return result",
        "    return x + y",
    }
end

describe("edit_alignment.strip_fences", function()
    it("strips a leading and trailing fence", function()
        assert.are_same({ "code" }, edit_alignment.strip_fences({ "```lua", "code", "```" }))
    end)

    it("leaves a partial fence alone", function()
        assert.are_same({ "```lua" }, edit_alignment.strip_fences({ "```lua" }))
    end)
end)

describe("edit_alignment.find_line_in_buffer", function()
    local lines = buffer_lines()

    it("finds an exact match near the cursor", function()
        -- cursor on line 3 (base0), look for "    return result" (base0 2)
        assert.equal(2, edit_alignment.find_line_in_buffer("    return result", lines, 3, 10))
    end)

    it("returns nil when there is no match", function()
        assert.is_nil(edit_alignment.find_line_in_buffer("    return zzz", lines, 3, 10))
    end)
end)

describe("edit_alignment.align", function()
    it("extracts a delta after a verbatim anchor", function()
        -- cursor at start of line "    return x + y" (base0 3)
        -- model repeats the anchor line then adds a new line
        local edit = edit_alignment.align(
            "    return x + y\n    return x * y",
            buffer_lines(), 3, 0)
        assert.is_not_nil(edit)
        assert.equal(3, edit.anchor_line_base0)
        assert.equal(3, edit.insertion_line_base0)
        assert.equal(0, edit.insertion_col_base0)
        assert.are_same({ "    return x * y" }, edit.insertion_lines)
    end)

    it("handles a fenced completion", function()
        local edit = edit_alignment.align(
            "```lua\n    return x + y\n    return x * y\n```",
            buffer_lines(), 3, 0)
        assert.is_not_nil(edit)
        assert.equal(3, edit.anchor_line_base0)
        assert.are_same({ "    return x * y" }, edit.insertion_lines)
    end)

    it("drops an echo of unchanged trailing context", function()
        -- model repeats the anchor line, adds a line, then echoes the next buffer line
        local edit = edit_alignment.align(
            "    return x + y\n    return x * y\n    return x + y",
            buffer_lines(), 3, 0)
        assert.is_not_nil(edit)
        assert.are_same({ "    return x * y" }, edit.insertion_lines)
    end)

    it("positions insertion at the cursor column when the anchor is the cursor line", function()
        local lines = {
            "def foo():",
            "    result = x + y",
            "    return x + y",
        }
        -- cursor mid-line: "    return " with cursor before "x + y"
        local edit = edit_alignment.align(
            "    return x + y\n    return x * y",
            lines, 2, 12)
        assert.is_not_nil(edit)
        assert.equal(2, edit.anchor_line_base0)
        assert.equal(12, edit.insertion_col_base0)
        assert.are_same({ "    return x * y" }, edit.insertion_lines)
    end)

    it("inserts a new line after the anchor when the anchor is above the cursor", function()
        local lines = {
            "def foo():",
            "    result = x + y",
            "    return result",
        }
        -- cursor on the last line; anchor is the line above (base0 1)
        local edit = edit_alignment.align(
            "    result = x + y\n    result = x * y",
            lines, 2, 0)
        assert.is_not_nil(edit)
        assert.equal(1, edit.anchor_line_base0)
        assert.equal(2, edit.insertion_line_base0)
        assert.are_same({ "    result = x * y" }, edit.insertion_lines)
    end)

    it("returns nil when no anchor is found", function()
        local edit = edit_alignment.align(
            "    return zzz\n    return qqq",
            buffer_lines(), 3, 0)
        assert.is_nil(edit)
    end)
end)
