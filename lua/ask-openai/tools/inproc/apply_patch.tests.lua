require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require "luassert"
local should = require("devtools.tests.should")
local describe = require('devtools.tests.define.describe')

local apply_patch = require("ask-openai.tools.inproc.apply_patch")

describe("apply_patch integration tests", function()
    it("add a file", function()
        -- use temp location so we don't create files in the repo when running tests
    end)

    it("immediate cancel does not create file", function()
        -- use temp location so we don't create files in the repo when running tests
        -- assert file not created for real real

    end)
end)
