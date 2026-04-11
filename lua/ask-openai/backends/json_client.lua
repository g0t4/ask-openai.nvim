local http = require("socket.http") -- luarocks install --local --lua-version=5.1 luasocket
-- BTW arch: sudo pacman --noconfirm -S lua51   -- to install lua 5.1
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
    local request_json = nil
    if request_body then
        request_json = vim.json.encode(request_body)
    end

    local curl_args = {
        "curl",
        "-sS",                      -- silent but show errors
        "-X", method,
        "-H", "Content-Type: application/json",
    }

    if request_json then
        table.insert(curl_args, "-d")
        table.insert(curl_args, request_json)
    end

    -- Append URL and ask curl to output HTTP status code on a new line
    table.insert(curl_args, url)
    table.insert(curl_args, "-w")
    table.insert(curl_args, "\n%{http_code}")

    -- Execute curl and capture output as a list of lines
    local output = vim.fn.systemlist(curl_args)

    -- The last line is the HTTP status code
    local http_code = tonumber(output[#output]) or 0
    -- All preceding lines form the response body
    table.remove(output)                     -- drop the status line
    local body_str = table.concat(output, "\n")

    ---@class JsonClientResponse
    ---@field code integer
    ---@field body any|nil
    local response = {
        code = http_code,
        body = vim.json.decode(body_str),
    }
    -- vim.print(response)
    return response
end

return JsonClient
