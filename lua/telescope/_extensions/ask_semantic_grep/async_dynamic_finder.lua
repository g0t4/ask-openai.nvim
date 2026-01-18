-- Adapted from telescope's DynamicFinder
-- wrap a function and pass callbacks for processing results and completing the query

local _telescope_find_callable_obj = function()
    local obj = {}

    obj.__index = obj
    obj.__call = function(t, ...)
        return t:_find(...)
    end

    obj.close = function() end

    return obj
end

local AsyncDynamicFinder = _telescope_find_callable_obj()

function AsyncDynamicFinder:new(opts)
    opts = opts or {}

    local obj = setmetatable({
        curr_buf = opts.curr_buf,
        fn = opts.fn,
        entry_maker = opts.entry_maker or make_entry.gen_from_string(opts),
    }, self)

    return obj
end

function AsyncDynamicFinder:_find(prompt, process_result, process_complete)
    self.fn(prompt, process_result, process_complete, self.entry_maker)
end

return AsyncDynamicFinder
