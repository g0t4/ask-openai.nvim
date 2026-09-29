require("ask-openai.helpers.test_setup").modify_package_path()
local raw_request = require("ask-openai.backends.raw_request")
local Counter = require('devtools.async.counter')
local should = require('devtools.tests.should')
local only = require('devtools.tests.only')
local log = require("devtools.logs.logger").universal()
local ansi = require("devtools.ansi")

describe("lookup IP addy", function()
    it("should resolve IP address", function()
        local counter = Counter:new()
        counter:increment()
        raw_request.query_inet_addy("dns.google.com", function(addy)
            -- print(addy)
            assert(addy == "8.8.4.4" or addy == "8.8.8.8")
            counter:decrement()
        end)
        counter:wait(500)
    end)
end)

describe("parse_headers", function()
    it("parses header string into table", function()
        local raw_headers = (
            [[
HTTP/1.1 200 OK
Server: llama.cpp
Access-Control-Allow-Origin:
Content-Type: application/json; charset=utf-8
Content-Length: 742
Connection: close
]])
        log:info(ansi.green(raw_headers))

        local parsed = raw_request.parse_headers(raw_headers)
        assert.is_table(parsed)
        assert.are.equal("application/json; charset=utf-8", parsed["content-type"])
        assert.are.equal("742", parsed["content-length"])

        assert.are_equal(parsed.status_code, '200')
        assert.are_equal(parsed.OK, true)
    end)
end)

describe("http", function()
    it("v1/models", function()
        local counter = Counter:new()
        counter:increment()
        local data = ""
        local body = nil
        raw_request.http({
            host = "paxy.lan",
            port = 8014,
            path = "/v1/models",
            method = "GET",
            body = body,
            on_data = function(chunk)
                data = data .. chunk
            end,
            on_done = function()
                counter:decrement()
            end
        })
        counter:wait(500)
        -- loose assertion that we get back viable data w/o worrying about specifics
        local models = vim.json.decode(data)
        assert.not_nil(models)
        assert.not_nil(models.data)
        -- vim.print(models.data)
    end)
end)

describe("http_events", function()
    describe("canceling", function()
        -- PRN add "sync close()" test if I ever need that
        it("async close() after 0ms", function()
            local counter = Counter:new()
            counter:increment()

            local body = {
                messages = { { role = "user", content = "What is your name?" }, },
                stream = true,
            }
            local tcp_handle = raw_request.http_events(
                {
                    host = "paxy.lan",
                    port = 8014,
                    path = "/v1/chat/completions",
                    method = "POST",
                    body = body,
                    on_done = function(err)
                        log:info("ON_DONE", ansi.yellow(err))
                    end,
                    on_data_value = function(data_value)
                        log:info("ON_DATA_VALUE", ansi.yellow(data_value))
                    end,
                })
            vim.defer_fn(function()
                tcp_handle:close(function()
                    counter:decrement()
                end)
            end, 0) -- delay close, else:  Assertion failed: (!(stream->flags & UV_HANDLE_CLOSING)), function uv__stream_io, file stream.c, line 1198.
            counter:wait(2500)
        end)
    end)

    it("/v1/chat/completions", function()
        local counter = Counter:new()
        counter:increment()

        local data = ""
        local body = {
            messages = {
                { role = "user", content = "What is your name?" },
            },
            max_tokens = 10,
            stream = true,
        }
        raw_request.http_events(
            {
                host = "paxy.lan",
                port = 8014,
                path = "/v1/chat/completions",
                method = "POST",
                body = body,
                on_done = function(err)
                    assert.is_nil(err)
                    counter:decrement()
                end,
                on_data_value = function(data_value)
                    log:info("ON_DATA_VALUE", ansi.yellow(data_value))
                end,
            })

        -- vim.print(data)
        counter:wait(2500)
    end)
end)

-- describe("fork data_only_parser to build on top of raw_request", function()
--     it("", function()
--         -- TODO merge this with my backends/sse/data_only_parser.lua but do so outside of the low level http client I have in raw_request
--     end)
-- end)
