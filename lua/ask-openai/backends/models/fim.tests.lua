require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require 'luassert'
local should = require('devtools.tests.should')
local describe = require('devtools.tests.define.describe')
local buffers = require('devtools.tests.buffers')

local fim = require('ask-openai.backends.models.fim')

describe("deepseek FIM", function()
    it("deepseek_tag() builds correctly", function()
        -- confirm deepseek_tag builder is working with empty segments for this one special token
        -- again my entire purpose for the builder is to make sure that we don't include full tokens in code that would mess up prompts
        -- including here, do not include full pad token:
        should.be_same(fim.deepseek_v4_flash.sentinel_tokens.PAD:sub(5, 13), '▁pad▁')
    end)
end)
