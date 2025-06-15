require('ask-openai.helpers.testing')
local ctags = require("ask-openai.prediction.context.ctags")
local matching_ctags = require("ask-openai.prediction.context.matching_ctags")
local should = require("devtools.tests.should")

describe("matching_ctags", function()
    it("requires", function()
        local maps_to = matching_ctags._require_for_file_path("lua/foo/bar.lua")
        should.be_equal(maps_to, "require('foo.bar')")
    end)

    it("get_context_item()", function()
        local item = matching_ctags.get_context_item_for("get_context_items")
        vim.print(item.content)

        local hardcoded = [[
lua/ask-openai/prediction/context/git_diff.lua
    function M.get_context_items()
lua/ask-openai/prediction/context/yanks.lua
    function M.get_context_item()
lua/ask-openai/prediction/context/matching_ctags.lua
    function M.get_context_item()
    function M.get_context_item_for(word)
lua/ask-openai/prediction/context/project.lua
    function M.get_context_items()
]]

        -- COOL!... now hopefully this helps suggest to use the requires!
        local hard_git_diff_with_require = [[
require('ask-openai.prediction.context.git_diff')
    function M.get_context_items()]]
        -- FYI end of [[]] needs to not have extra newlines / chars
        assert.is.not_nil(string.find(item.content, hard_git_diff_with_require, 1, true))

        local hard_git_diff = [[
lua/ask-openai/prediction/context/git_diff.lua
    function M.get_context_items()]]
        -- assert.is.not_nil(string.find(item.content, hard_git_diff, 1, true))
    end)
end)
