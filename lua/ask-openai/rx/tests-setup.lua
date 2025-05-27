local assert = require 'luassert'
require("ask-openai.helpers.test_setup").modify_package_path()

local function is_gt(state, arguments)
    local expected = arguments[1]
    return function(value)
        return value > expected
    end
end
assert:register("matcher", "gt", is_gt)
