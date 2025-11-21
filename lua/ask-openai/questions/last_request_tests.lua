local LastRequestForThread = require("ask-openai.questions.last_request_for_thread")
local LastRequest = require("ask-openai.backends.last_request")

describe("LastRequestForThread", function()
    it(":new()", function()
        -- I am still wrapping my mind around inheritance like behavior in lua...
        -- so I am writing a test with my expectations, that way I can tinker with the
        -- setup of metatables/__index and verify it is doing what I think

        local body = {}
        local request = LastRequestForThread:new(body)

        assert.equal(request.body, body, "should have fields from LastRequest (parent type)")
        assert.same(request.accumulated_model_response_messages, {}, "should have fields from LastRequestForThread too")

        assert.equal(request.terminate, LastRequest.terminate, "should have methods from LastRequest")
        assert.equal(request.test, LastRequestForThread.test, "should have methods from LastRequestForThread too")
    end)
end)
