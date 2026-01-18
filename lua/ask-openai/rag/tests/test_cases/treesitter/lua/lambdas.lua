local runner = TestRunner:new()
-- TODO! should anonymous functions (lambdas) be chunked alone or just leave them alone, especially when they are passed to a function argument?
runner:add_test(function()
    return 1 + 1 == 2
end, true)
runner:add_test(function()
    return "hello" == "world"
end, false)
runner:run_tests()
