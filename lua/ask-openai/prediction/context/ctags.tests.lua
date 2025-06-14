require('ask-openai.helpers.testing')
local ctags = require("ask-openai.prediction.context.ctags")
local should = require("devtools.tests.should")

describe("integration test tags file", function()
    it("find_tag_file PLACEHOLDER", function()
        -- TODO placeholder for when I need something more sophisticated than just "tags"
        local file = ctags.find_tags_for_this_project()
        should.be_equal("tags", file)
    end)

    it("get_tag_lines", function()
        local lines = ctags.read_file_lines("tags")
        local num_tags = #lines -- use for expect which only handles showing primitives (not tables nor operations)
        print("original tag count: " .. tostring(num_tags))
        expect(num_tags > 0)

        local filtered = ctags.parse_tag_lines(lines, "lua")
        print("filtered count: " .. tostring(#filtered))
        expect(#filtered > 0)

        -- dump reassembled to file to inspect manually
        local reassembled = ctags.reassemble_tags(filtered)
        local filename = "tmp/reassembled_tags.txt"
        local handle = io.open(filename, "w")
        handle:write(reassembled)
        handle:close()
    end)
end)

describe("u-ctags format", function()
    -- right now assuming u-ctags format, could add more in future
    -- https://docs.ctags.io/en/latest/man/tags.5.html#tags-5

    describe("parse_ctags", function()
        it("splits on \t", function()
            local lines = {
                "on_delete	lua/devtools/diff/weslcs.lua	/^    function builder:on_delete(_token)$/;\"	f	unknown:builder",
                "on_delete	lua/devtools/diff/weslcs.lua	/^    function builder:on_delete(token)$/;\"	f	unknown:builder}",
                "sort	lua/devtools/super_iter.lua	/^    iter.sort = function(self, cmp_fn)$/;\"	f	unknown:iter",
                "sorted	lua/devtools/super_iter.tests.lua	/^        local sorted = super_iter(unsorted):sort(function(a, b) return a > b end):totable()$/;\"	f",
            }
            local tags = ctags.parse_tag_lines(lines, "lua")
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
        describe("filter tag lines", function()
            it("removes local symbols", function()
                local lines = {
                    -- strip these:
                    "split_lines_to_table	lua/ask-openai/prediction/prediction.lua	/^local function split_lines_to_table(text)$/;\"	f",
                    "tool_header	lua/ask-openai/questions/ask.lua	/^            local tool_header = \"**\" .. (call[\"function\"].name or \"\") .. \"**\"$/;\"	f",
                    -- keep lines:
                    "on_delete	lua/devtools/diff/weslcs.lua	/^    function builder:on_delete(_token)$/;\"	f	unknown:builder",
                }
                local tags = ctags.parse_tag_lines(lines, "lua")
                expect(#tags == 1)
                local only = tags[1]
                -- FYI this is not a test of parsing, so only verify the one item looks approx right
                should.be_same(only.tag_name, "on_delete")
            end)

            it("excludes pseudo tags / metadata lines (starts with !) and comments", function()
                local lines = {
                    "#_TAG_EXTRA_DESCRIPTION",
                    "function1	lua/ask-openai/prediction/prediction.lua	/^function split_lines_to_table(text)$/;\"	f",
                    "!_TAG_FIELD_DESCRIPTION",
                    "function2	lua/ask-openai/prediction/prediction.lua	/^function split_lines_to_table(text)$/;\"	f",
                }
                local tags = ctags.parse_tag_lines(lines, "lua")
                expect(#tags == 2)
                local first = tags[1]
                local second = tags[2]
                should.be_same(first.tag_name, "function1")
                should.be_same(second.tag_name, "function2")
            end)

            it("excludes files with .tests. in name", function()
                local lines = {
                    "sort	lua/devtools/super_iter.lua	/^    iter.sort = function(self, cmp_fn)$/;\"	f	unknown:iter",
                    "sorted	lua/devtools/super_iter.tests.lua	/^        local sorted = super_iter(unsorted):sort(function(a, b) return a > b end):totable()$/;\"	f",
                }
                local tags = ctags.parse_tag_lines(lines, "lua")
                expect(#tags == 1)
                local first = tags[1]
                should.be_same(first.tag_name, "sort")
            end)

            it("excludes non-lua files when language=lua", function()
                local lines = {
                    "sort	lua/devtools/super_iter.lua	/^function(self, cmp_fn)$/;\"	f	unknown:iter",
                    "sort	lua/devtools/super_iter.py	/^function(self, cmp_fn)$/;\"	f	unknown:iter",
                }
                local tags = ctags.parse_tag_lines(lines, "lua")
                expect(#tags == 1)
                local first = tags[1]
                should.be_same(first.tag_name, "sort")
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


        describe("re-assemble SPIKE", function()
            it("try this", function()
                local lines = {
                    "on_delete	lua/devtools/diff/weslcs.lua	/^    function builder:on_delete(_token)$/;\"	f	unknown:builder",
                    "on_delete	lua/devtools/diff/weslcs.lua	/^    function builder:on_delete(token)$/;\"	f	unknown:builder}",
                    "sort	lua/devtools/super_iter.lua	/^    iter.sort = function(self, cmp_fn)$/;\"	f	unknown:iter",
                }

                local expected_linesA = {
                    "lua/devtools/diff/weslcs.lua",
                    "    function builder:on_delete(_token)",
                    "    function builder:on_delete(token)",
                    "lua/devtools/super_iter.lua",
                    "    iter.sort = function(self, cmp_fn)",
                }

                local expected_linesB = {
                    "lua/devtools/super_iter.lua",
                    "    iter.sort = function(self, cmp_fn)",
                    "lua/devtools/diff/weslcs.lua",
                    "    function builder:on_delete(_token)",
                    "    function builder:on_delete(token)",
                }

                local tags = ctags.parse_tag_lines(lines, "lua")
                local assembled = ctags.reassemble_tags(tags)

                -- FYI right now I cannot guarantee the order of the two groups is the same
                --   so I check that either way, the corresponding lines match per group
                --   PRN... any way to make the order predictable for the tests w/o altering the impl?
                --   OR, should I sort keys (filenames) or?
                local expected_reassembledA = table.concat(expected_linesA, "\n")
                local expected_reassembledB = table.concat(expected_linesB, "\n")
                local either = assembled == expected_reassembledA or assembled == expected_reassembledB
                if not either then
                    print("\n")
                    print("## reassembled: ")
                    print(assembled)
                    print("## expectedA: ")
                    print(expected_reassembledA)
                    print("## expectedB: ")
                    print(expected_reassembledB)
                    print("\n")
                end
                assert(either)
            end)
        end)
    end)
end)
