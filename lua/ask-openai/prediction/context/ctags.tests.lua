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
    describe("filtering lines", function()
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

            -- https://docs.ctags.io/en/latest/man/ctags.1.html
            -- u-ctags format
            -- <tag_name><TAB><file_name><TAB><ex_cmd>;"<TAB><extension_fields>

            local expected = {
                tag_name = "on_delete",
                file_name = "lua/devtools/diff/weslcs.lua",
                -- make sure to strip delimiter ;" at the end of the ex_command
                ex_command = "/^    function builder:on_delete(token)$/",
                -- FOR NOW I am not gonna use extras... so skip it
            }
            should.be_same(expected, second)
        end)


        -- LUA specific:
        --  drop local functions/vars/etc (only those in the current file, in the PSM already... will matter)
        --     /^local function simulate_rewrite_instant_one_chunk(opts)$/;"
        --     /^            local tool_header = "**" .. (call["function"].name or "") .. "**"$/;"
        --
        describe("filter_parsed_tags", function()
            it("removes local symbols", function()
                local lines = {
                    -- strip these:
                    "split_lines_to_table	lua/ask-openai/prediction/prediction.lua	/^local function split_lines_to_table(text)$/;\"	f",
                    "tool_header	lua/ask-openai/questions/ask.lua	/^            local tool_header = \"**\" .. (call[\"function\"].name or \"\") .. \"**\"$/;\"	f",
                    -- keep lines:
                    "on_delete	lua/devtools/diff/weslcs.lua	/^    function builder:on_delete(_token)$/;\"	f	unknown:builder",
                }
                local tags = ctags.parse_tag_lines(lines)
                local filtered = ctags.filter_parsed_tags(tags)
                local expected_keep_lines = { tags[3] }
                should.be_same(expected_keep_lines, filtered)
            end)
        end)


        describe("re-assemble SPIKE", function()
            it("try this", function()
                local lines = {
                    "on_delete	lua/devtools/diff/weslcs.lua	/^    function builder:on_delete(_token)$/;\"	f	unknown:builder",
                    "on_delete	lua/devtools/diff/weslcs.lua	/^    function builder:on_delete(token)$/;\"	f	unknown:builder}",
                    "sort	lua/devtools/super_iter.lua	/^    iter.sort = function(self, cmp_fn)$/;\"	f	unknown:iter",
                }
            end)
        end)
    end)
end)
