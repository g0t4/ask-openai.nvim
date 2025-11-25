local http = require("socket.http") -- luarocks install --lua-version=5.1  luasocket
local ltn12 = require("ltn12") -- also from luasocket

local JsonClient = {
    ---@enum Methods
    Methods = {
        GET = "GET",
        POST = "POST",
    }
}

--- PRN rename to HttpClient? right now it's only for JSON so let's leave it to convey that purpose
---@param url string
---@param method Methods
---@param request_body? table
---@return JsonClientResponse?
function JsonClient.get_response_body(url, method, request_body)
    local response_body = {}
    local source = nil
    if request_body then
        local request_body_json = vim.json.encode(request_body)
        source = ltn12.source.string(request_body_json)
    end
    local res, code, headers, status = http.request {
        url = url,
        method = method,
        headers = {
            ["Content-Type"] = "application/json",
        },
        source = source,
        sink = ltn12.sink.table(response_body),
    }

    local body = table.concat(response_body)

    -- FYI if decode fails, will throw so no need to verify anything else in that case!

    ---@class JsonClientResponse
    ---@field code integer
    ---@field body any|nil
    local response = {
        code = code,
        body = vim.json.decode(body)
    }
    -- vim.print(response)
    return response
end

return JsonClient
