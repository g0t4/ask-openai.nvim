local instructs = require("ask-openai.frontends.instructs")
require('ask-openai.helpers.testing')
local describe = require("devtools.tests._describe")

describe("clean_content", function()
    it("trims leading and trailing whitespace", function()
        local raw = "   Hello world   "
        local cleaned = instructs.clean_contents(raw)
        assert.are_equal("Hello world", cleaned)
    end)

    it("removes HTML comments", function()
        local raw = "<!-- comment -->Hello"
        local cleaned = instructs.clean_contents(raw)
        assert.are_equal("Hello", cleaned)
    end)

    it("removes HTML comments non‑greedily", function()
        local raw = "Hello <!-- first comment -->world random -->!"
        local cleaned = instructs.clean_contents(raw)
        -- make sure the stripping doesn't go past end of current comment
        assert.are_equal("Hello world random -->!", cleaned)
    end)

    it("removes YAML front‑matter", function()
        local raw = [[---
foo: bar
---
Hello world]]
        local cleaned = instructs.clean_contents(raw)
        assert.are_equal("Hello world", cleaned)
    end)

    it("removes BOTH - HTML comments and YAML front‑matter", function()
        local raw = [[---
foo: bar
---
<!-- comment -->  Hello   ]]
        local cleaned = instructs.clean_contents(raw)
        assert.are_equal("Hello", cleaned)
    end)

    it("yaml frontmatter not on first line", function()
        local raw = [[foo
---
bar: baz
---
Hello world]]
        local cleaned = instructs.clean_contents(raw)
        assert.are_equal(raw, cleaned)
    end)

    it("removes multiple HTML comments and trims", function()
        local raw = "Hello <!--c1--> world <!--c2-->"
        local cleaned = instructs.clean_contents(raw)
        -- Expected: comments removed, leading/trailing whitespace trimmed, internal double space retained.
        assert.are_equal("Hello  world", cleaned)
    end)
end)
