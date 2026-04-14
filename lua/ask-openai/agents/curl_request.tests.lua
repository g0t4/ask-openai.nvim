require('ask-openai.helpers.testing')
local describe = require("devtools.tests._describe")
local CurlRequestForTrace = require("ask-openai.agents.curl_request_for_trace")
local CurlRequest = require("ask-openai.backends.curl_request")
require("ask-openai.backends.curl") -- for _G.CompletionsEndpoints

describe("CurlRequestForTrace", function()
    it(":new()", function()
        -- I am still wrapping my mind around inheritance like behavior in lua...
        -- so I am writing a test with my expectations, that way I can tinker with the
        -- setup of metatables/__index and verify it is doing what I think

        local params = { body = {}, base_url = "base_url", endpoint = CompletionsEndpoints.oai_v1_chat_completions }
        local request = CurlRequestForTrace:new(params)

        assert.equal(request.body, params.body, "should have fields from CurlRequest (parent type)")
        assert.equal(request.base_url, "base_url")
        assert.equal(request.endpoint, CompletionsEndpoints.oai_v1_chat_completions)
        assert.same(request.accumulated_model_response_messages, {}, "should have fields from CurlRequestForTrace too")

        assert.equal(request.terminate, CurlRequest.terminate, "should have methods from CurlRequest")
        assert.equal(request.test, CurlRequestForTrace.test, "should have methods from CurlRequestForTrace too")
    end)

    it("has terminate on class", function()
        assert.equal(CurlRequestForTrace.terminate, CurlRequest.terminate, "CurlRequestForTrace.terminate is missing")
    end)
end)
