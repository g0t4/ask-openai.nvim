require("ask-openai.helpers.test_setup").modify_package_path()

local FIMPerformance = require("ask-openai.predictions.fim_performance")

describe("FIMPerformance", function()
    it("two instances differ", function()
        local perf1 = FIMPerformance:new()
        local perf2 = FIMPerformance:new()
        assert.are.not_same(perf1, perf2)


        assert.are.not_same(perf1._prediction_start_time_ns, perf2._prediction_start_time_ns)
        -- rag_done() called twice was issue with how I messed up metatable so use that here:
        perf1:rag_started()
        perf1:rag_done()
        perf2:rag_started()
        perf2:rag_done()
    end)
end)
