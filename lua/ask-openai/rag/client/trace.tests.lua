local trace = require("ask-openai.rag.client.trace")

describe("RAG traces", function()
    local original_stdpath
    local temp_state

    before_each(function()
        temp_state = vim.fn.tempname()
        vim.fn.mkdir(temp_state, "p")
        original_stdpath = vim.fn.stdpath
        vim.fn.stdpath = function(kind)
            if kind == "state" then
                return temp_state
            end
            return original_stdpath(kind)
        end
    end)

    after_each(function()
        vim.fn.stdpath = original_stdpath
        vim.fn.delete(temp_state, "rf")
    end)

    it("stores the request, ranked response, source, and timing", function()
        local active = trace.start("telescope", {
            query = "transcription edit boundary",
            instruct = "Find code related to the user's query",
            topK = 50,
        })
        local path = assert(trace.save(active, {
            result = {
                matches = {
                    {
                        file = "/repo/builder.py",
                        text = "def finish_edit(): pass",
                        embed_score = 0.72,
                        embed_rank = 3,
                        rerank_score = 0.94,
                        rerank_rank = 1,
                    },
                },
            },
        }))

        assert.matches("/ask%-openai/rag/telescope/%d+%-trace%.json$", path)
        local file = assert(io.open(path, "r"))
        local saved = vim.json.decode(file:read("*a"))
        file:close()

        assert.equals("rag", saved.type)
        assert.equals("telescope", saved.source)
        assert.equals("transcription edit boundary", saved.request_body.query)
        assert.equals(0.94, saved.response.result.matches[1].rerank_score)
        assert.is_number(saved.duration_ms)
        assert.is_nil(saved._started_ms)
    end)
end)
