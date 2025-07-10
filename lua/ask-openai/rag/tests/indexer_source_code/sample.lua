

local TestRunner = {}

function TestRunner:new()
    local tests = {}
    local results = {}
    return setmetatable({
        tests = tests,
        results = results,
        add_test = function(self, test_func, expected)
            table.insert(self.tests, {test_func = test_func, expected = expected})
        end,
        run_tests = function(self)
            for _, test in ipairs(self.tests) do
                local ok, result = pcall(test.test_func)
                if ok and result == test.expected then
                    table.insert(self.results, {status = "pass", message = "Test passed"})
                else
                    table.insert(self.results, {status = "fail", message = "Test failed: expected " .. tostring(test.expected) .. ", got " .. tostring(result)})
                end
            end
        end
    }, {__index = TestRunner})
end

-- Example usage
local runner = TestRunner:new()
runner:add_test(function()
    return 1 + 1 == 2
end, true)
runner:add_test(function()
    return "hello" == "world"
end, false)
runner:run_tests()

for _, result in ipairs(runner.results) do
    print(result.status .. ": " .. result.message)
end


