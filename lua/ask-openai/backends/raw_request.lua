local log = require("devtools.logs.logger").universal()
local ansi = require("devtools.ansi")
local uv = vim.uv
local perf = require("devtools.performance")


-- !!! FYI this is just a spike of an idea to reduce dependence on curl externally
-- it would probably be best to find an http client I like that is async and in-process
-- OR perhaps just keep curl and up your `ulimit -Sn` to more than 256 to avoid `too many files open warning`
-- FYI if you don't like this, you should consider moving back to curl OR... another in-process http client
-- FYI doubtful I can get https working BTW


local M = {}

local host_address_cache = {}

function M.query_inet_addy(host, on_first_ip_address)
    -- for my use case, I will restart neovim if I change DNS which I do almost NEVER
    local cached_address = host_address_cache[host]
    if cached_address then
        on_first_ip_address(cached_address)
        return
    end
    -- local start_ns = perf.get_time_in_ns()
    vim.uv.getaddrinfo(host, nil, {}, function(err, addresses)
        -- local duration_ns = perf.get_time_in_ns() - start_ns
        -- log:info(string.format("DNS lookup for %s took %.2f ms", host, duration_ns / 1e6))

        assert(not err, err)
        for _, addr in ipairs(addresses) do
            if addr.family:gmatch("^inet") and addr.protocol == "tcp" then
                local first_address = addr.addr
                host_address_cache[host] = first_address
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
---@return uv.uv_tcp_t tcp_handle
function M.http(request)
    on_headers = request.on_headers or function() end
    -- FYI https://docs.libuv.org/en/v1.x/tcp.html for uv_tcp_t
    local tcp_handle, newtcp_err, newtcp_err_name = uv.new_tcp()
    log:info("new tcp_handle", tcp_handle)

    assert(tcp_handle ~= nil)
    if newtcp_err ~= nil then
        log:error("uv.new_tcp failed", newtcp_err, newtcp_err_name)
    end

    M.query_inet_addy(request.host, function(first_ip)
        host_ip = first_ip
        local headers_done = false

        if tcp_handle:is_closing() then
            return -- defensive, in case close is called before we connect, not likely to happen in reality
        end
        local conn, conn_err, conn_err_name = tcp_handle:connect(host_ip, request.port, function(inner_err)
            if inner_err then
                if inner_err:find("ECANCELED") then
                    log:info("ECANCELED detected, turn this into an ignore if it is tied to close, BTW tcp_handle:is_closing():", tcp_handle:is_closing())
                end
                log:error('tcp_handle:connect failed', inner_err, request)
                log:info('  FYI tcp_handle:is_closing()', tcp_handle:is_closing())
                if tcp_handle:is_closing() then
                    log:info("  tcp_handle already closing, not calling close again")
                else
                    -- TODO centralize one spot to avoid calling close twice
                    tcp_handle:close()
                end
                return request.on_done('tcp_handle:connect failed: ' .. inner_err)
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

            tcp_handle:write(message)

            local buffer = ""

            -- local first_n = 10

            tcp_handle:read_start(function(read_err, chunk)
                -- if first_n > 0 then
                --     first_n = first_n - 1
                --     -- 61ms to 88ms - with alt+tab on line right before this, also 65ms often (so prompt is fully cached) => put cursor above this line
                --     local now_ns = perf.get_time_in_ns()
                --     local duration_ns = now_ns - request.start_ns
                --     local duration_ms = duration_ns / 1e6
                --     -- log:info(string.format("tcp time_to_first_data_value =%f", duration_ms))
                --     -- log:info("CHUNK", chunk)
                -- end

                -- here is same as curl
                if read_err then
                    tcp_handle:close()
                    return request.on_done(read_err)
                end

                if not chunk then
                    tcp_handle:close()
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
        -- FYI likely can ignore ECANCELED as that would be me calling tcp_handle:close() during connection
        log:info("connect results", conn, conn_err, conn_err_name)
    end)
    return tcp_handle
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
---@return uv.uv_tcp_t tcp_handle
function M.http_events(request)
    local SSEDataOnlyParser = require("ask-openai.backends.sse.data_only_parser")
    parser = SSEDataOnlyParser.new(function(sse)
        request.on_data_value(sse)
    end)

    local raw = {
        -- start_ns = request.start_ns, -- FYI just for perf testing, nuke when done with that
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
