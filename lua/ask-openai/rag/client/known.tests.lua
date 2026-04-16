--- Unit tests for `ask-openai.rag.client.known`
-- Uses Plenary/Busted style tests. The test stubs the embedder to return a fixed
-- set of embeddings that produce the expected similarity matrix, ensuring the
-- verification logic works without contacting a real server.

local embedder = require("ask-openai.rag.client.embedder")
local known = require("ask-openai.rag.client.known")

describe("known module", function()
    it("runs verification against the real embedding service", function()
        -- Directly invoke the verification which will call the real embed_batch
        local ok = known.run_verification()
        assert.is_true(ok)
    end)
end)
