local log = require("devtools.logs.logger").universal()
local ansi = require("devtools.ansi")
local uv = vim.uv


-- !!! FYI this is just a spike of an idea to reduce dependence on curl externally
-- it would probably be best to find an http client I like that is async and in-process
-- OR perhaps just keep curl and up your `ulimit -Sn` to more than 256 to avoid `too many files open warning`

local M = {}
function M.query_inet_addy(host, on_first_ip_address)
    vim.uv.getaddrinfo(host, nil, {}, function(err, addresses)
        assert(not err, err)
        -- log:info(addresses)
        for _, addr in ipairs(addresses) do
            if addr.family:gmatch("^inet") and addr.protocol == "tcp" then
                local first_address = addr.addr
                -- log:info("first address", first_address)
                on_first_ip_address(first_address)
                return
            end
        end
    end)
end

---@class RawRequestHeaders
---@field status_code string
---@field OK boolean
---@field chunked boolean
---@field [string] string

---@param raw_headers string
---@return RawRequestHeaders
function M.parse_headers(raw_headers)
    -- * fixed headers case:
    -- Content-Type: application/json; charset=utf-8
    -- Content-Length: 742

    -- * chunked response (no fixed length)
    -- Content-Type: text/event-stream
    -- Transfer-Encoding: chunked

    local headers = {}
    local first_line = true
    for line in raw_headers:gmatch("[^\r\n]+") do
        if first_line then
            first_line = false
            headers.status_code = line:match("^HTTP/%d+%.%d+ (%d+)") or ""
            headers.OK = headers.status_code == "200"
        else
            local name, value = line:match("^([^:]+):%s*(.*)")
            if name and value then
                headers[name:lower()] = value
            end
        end
    end

    -- * chunked or not
    -- perhaps this warning does not belong here, leave it for now
    headers.chunked = headers["transfer-encoding"] == "chunked"

    return headers
end

---@class HttpRawRequest
---@field host string
---@field port number
---@field path string
---@field method string
---@field body? table
---@field on_data fun(data: string)
---@field on_done fun(err?: string)
---@field on_headers? fun(headers: RawRequestHeaders)

---@param request HttpRawRequest
---@return userdata
function M.http(request)
    on_headers = request.on_headers or function() end
    local tcp = assert(uv.new_tcp())
    M.query_inet_addy(request.host, function(first_ip)
        host_ip = first_ip
        local headers_done = false

        tcp:connect(host_ip, request.port, function(err)
            if err then
                tcp:close()
                return request.on_done(err)
            end

            local body_json = ""
            if request.body ~= nil then
                body_json = vim.json.encode(request.body)
            end

            local headers = request.method .. " " .. request.path .. " HTTP/1.1\r\n" ..
                "Host: " .. request.host .. ":" .. request.port .. "\r\n" ..
                "Accept: text/event-stream\r\n" ..
                "Connection: close\r\n"

            if request.body ~= nil then
                headers = headers ..
                    "Content-Type: application/json\r\n" ..
                    "Content-Length: " .. #body_json .. "\r\n"
            end

            local message = headers .. "\r\n"
                .. body_json

            -- log:info('message', message)

            tcp:write(message)

            local buffer = ""
            tcp:read_start(function(read_err, chunk)
                if read_err then
                    tcp:close()
                    return request.on_done(read_err)
                end

                if not chunk then
                    tcp:close()
                    return request.on_done()
                end

                -- log:info('chunk', chunk)
                buffer = buffer .. chunk

                if not headers_done then
                    local _, body_start = buffer:find("\r\n\r\n", 1, true)

                    if body_start then
                        headers_done = true
                        local headers_raw = buffer:sub(1, body_start)
                        local headers = M.parse_headers(headers_raw)
                        -- TODO look at headers to find if fixed lenght Content-Length OR stream
                        --   TODO and if streaming => need to parse the length at the start of each "chunk" and then read exactly that and then wait for next length
                        --   TODO if not streaming => read content-length chars and stop (I suppose warn if more than that?)
                        -- log:info("headers", headers)
                        on_headers(headers)

                        -- dregs after headers would be start of body, so `on_data` it!
                        local body = chunk:sub(body_start + 1)
                        if #body > 0 then
                            -- log:info(ansi.green_bold("ON_DATA(header_dregs)"), vim.inspect(body))
                            request.on_data(body)
                        end
                    end

                    return
                end

                -- log:info(ansi.green_bold("ON_DATA"), vim.inspect(chunk))
                request.on_data(chunk)
            end)
        end)
    end)
    return tcp
end

---@class HttpRawRequestForEvents
---@field host string
---@field port number
---@field path string
---@field method string
---@field body? table
---@field on_data_value fun(data_value: string)
---@field on_done fun(err: string)

---@param request HttpRawRequestForEvents
---@return userdata
function M.http_events(request)
    local SSEDataOnlyParser = require("ask-openai.backends.sse.data_only_parser")
    parser = SSEDataOnlyParser.new(function(sse)
        request.on_data_value(sse)
    end)

    local raw = {
        host = request.host,
        port = request.port,
        path = request.path,
        method = request.method,
        body = request.body,
        on_data = function(data)
            -- ❤️ that my existing SSEDataOnlyParser fits perfectly into my new raw request client
            -- FYI consumers of http_events should not set these...
            parser:write(data)
        end,
        on_done = function(err)
            local dregs_error = parser:flush_dregs()
            if dregs_error ~= nil then
                -- PRN do not swallow passed err too? if both have info?
                request.on_done(dregs_error)
                return
            end
            request.on_done(err)
        end,
        on_headers = function(headers)
            if not headers.OK then
                log:warn("Non-OK status code: %s", headers.status_code)
            end
            if not headers.chunked then
                log:warn(string.format("Expected transfer-encoding: chunked, got headers: %s", vim.inspect(headers)))
            end
        end,
    }
    return M.http(raw)
end

return M
