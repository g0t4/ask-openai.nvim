require('ask-openai.helpers.testing')
local ctags = require("ask-openai.prediction.context.ctags")
local should = require("devtools.tests.should")

describe("integration test tags file", function()
    it("find_tag_file PLACEHOLDER", function()
        -- TODO placeholder for when I need something more sophisticated than just "tags"
        local file = ctags.find_tag_file()
        should.be_equal("tags", file)
    end)

    it("get_tag_lines", function()
        local tags = ctags.get_tag_lines("tags")
        local num_tags = #tags -- use for expect which only handles showing primitives (not tables nor operations)
        print("original tag count: " .. tostring(num_tags))
        expect(num_tags > 0)

        local filtered = ctags.filter_tag_lines(tags)
        print("filtered count: " .. tostring(#filtered))
        expect(#filtered > 0)
    end)
end)

describe("u-ctags format", function()
    -- right now assuming u-ctags format, could add more in future
    -- https://docs.ctags.io/en/latest/man/tags.5.html#tags-5
    describe("filter_tag_lines", function()
        it("excludes comment lines", function()

        end)

        it("excludes pseudo tags / metadata lines (starts with !) and comments", function()
            local lines = {
                "#_TAG_EXTRA_DESCRIPTION",
                "function1",
                "!_TAG_FIELD_DESCRIPTION",
                "function2",
            }
            local filtered = ctags.filter_tag_lines(lines)
            local expected = { "function1", "function2" }
            should.be_same(expected, filtered)
        end)
        local lines = {
            "on_delete	lua/devtools/diff/weslcs.lua	/^    function builder:on_delete(_token)$/;\"	f	unknown:builder",
            "on_delete	lua/devtools/diff/weslcs.lua	/^    function builder:on_delete(token)$/;\"	f	unknown:builder}",
            "sort	lua/devtools/super_iter.lua	/^    iter.sort = function(self, cmp_fn)$/;\"	f	unknown:iter",
            "sorted	lua/devtools/super_iter.tests.lua	/^        local sorted = super_iter(unsorted):sort(function(a, b) return a > b end):totable()$/;\"	f",
        }

        it("excludes files with .tests. in name", function()
            local lines = {
                "sort	lua/devtools/super_iter.lua	/^    iter.sort = function(self, cmp_fn)$/;\"	f	unknown:iter",
                "sorted	lua/devtools/super_iter.tests.lua	/^        local sorted = super_iter(unsorted):sort(function(a, b) return a > b end):totable()$/;\"	f",
            }
            local filtered = ctags.filter_tag_lines(lines)
            local expected = { lines[1] }
            should.be_same(expected, filtered)
        end)
        -- TODO! filter by language of file completing in
        --
        --
        -- *** in dotfiles...
        -- nvim / hammerspoon s/b separated for tags
        --   architectually... I should probably only generate a tags file in the parent most dir related and name by language then
        --    OR I need a config mechanism to NOT just use global tags
        -- cat tags | grep "nvim.*\.lua" | wordcount
    end)

    describe("parse_ctags", function()
        it("splits on \t", function()
            local lines = {
                "on_delete	lua/devtools/diff/weslcs.lua	/^    function builder:on_delete(_token)$/;\"	f	unknown:builder",
                "on_delete	lua/devtools/diff/weslcs.lua	/^    function builder:on_delete(token)$/;\"	f	unknown:builder}",
                "sort	lua/devtools/super_iter.lua	/^    iter.sort = function(self, cmp_fn)$/;\"	f	unknown:iter",
                "sorted	lua/devtools/super_iter.tests.lua	/^        local sorted = super_iter(unsorted):sort(function(a, b) return a > b end):totable()$/;\"	f",
            }
            local tags = ctags.parse_tag_lines(lines)
            local second = tags[2]
            local expected = {
                name = "on_delete",
                filename = "lua/devtools/diff/weslcs.lua",
                line = "/^    function builder:on_delete(token)$/;\"",
                kind = "f",
                extras = "unknown:builder}",
            }
            should.be_same(expected, second)
        end)
    end)
end)
