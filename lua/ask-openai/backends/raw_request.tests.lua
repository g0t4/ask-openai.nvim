require("ask-openai.helpers.test_setup").modify_package_path()
local raw_request = require("ask-openai.backends.raw_request")
local Counter = require('devtools.async.counter')
local should = require('devtools.tests.should')
local only = require('devtools.tests.only')
local log = require("devtools.logs.logger").universal()
local ansi = require("devtools.ansi")

local NOOP = function() end

describe("lookup IP addy", function()
    it("should resolve IP address", function()
        local counter = Counter.one()
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
        local counter = Counter.one()
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
            local counter = Counter.one()

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

    describe("connection failure", function()
        -- PRN add "sync close()" test if I ever need that
        it("async close() after 0ms", function()
            local counter = Counter.one()

            local body = {
                messages = { { role = "user", content = "What is your name?" }, },
                stream = true,
            }
            local done_err = nil
            local tcp_handle = raw_request.http_events(
                {
                    host = "paxy.lan", -- host must resolve
                    port = 8090, -- port must not be listening
                    path = "/v1/chat/completions",
                    method = "POST",
                    body = body,
                    on_done = function(err)
                        done_err = err
                        counter:decrement()
                    end,
                    on_data_value = NOOP,
                })
            counter:wait(2500) -- FYI invalid port on a valid host can take a second to fail
            assert(done_err)
            assert.has_string(done_err, "ECONNREFUSED")
        end)
    end)


    it("/v1/chat/completions", function()
        local counter = Counter.one()
        -- FYI! you can cleanup cruft/duplication later in these tests

        local body = {
            messages = {
                { role = "user", content = "What is your name?" },
            },
            max_tokens = 10,
            stream = true,
        }
        local done_err = nil
        raw_request.http_events(
            {
                host = "paxy.lan",
                port = 8014,
                path = "/v1/chat/completions",
                method = "POST",
                body = body,
                on_done = function(err)
                    done_err = err
                    counter:decrement()
                end,
                on_data_value = NOOP, -- PRN capture and assert on the data?
            })

        counter:wait(2500)
        assert.is_nil(done_err, "should not have a failure on_done")
    end)
end)

describe("fragmented HTTP responses", function()
    local new_tcp, query_address
    local reads
    before_each(function()
        new_tcp, query_address = vim.uv.new_tcp, raw_request.query_inet_addy
        reads = {}
        raw_request.query_inet_addy = function(_, cb) cb("127.0.0.1") end
        vim.uv.new_tcp = function()
            return {
                connect = function(_, _, _, cb) cb() end,
                read_start = function(_, cb) table.insert(reads, cb) end,
                write = NOOP,
                is_closing = function() return false end,
                close = NOOP,
            }
        end
    end)

    after_each(function()
        vim.uv.new_tcp, raw_request.query_inet_addy = new_tcp, query_address
    end)

    local function start()
        local result = { events = {}, done = 0 }
        raw_request.http_events({
            host = "localhost", port = 80, method = "GET", path = "/",
            on_data_value = function(value) table.insert(result.events, value) end,
            on_done = function(err)
                result.done = result.done + 1
                result.err = err
            end,
        })
        return result, reads[#reads]
    end

    it("delivers a split JSON error and keeps an overlapping SSE request independent", function()
        local failed, fail_read = start()
        local success, success_read = start()
        fail_read(nil, "HTTP/1.1 400 Bad Request\r\nContent-Length: 37\r\n\r")
        success_read(nil, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n")
        fail_read(nil, '\n{"error":{"message":"context ')
        success_read(nil, "\r\ne\r\ndata: [DONE]\n\n")
        fail_read(nil, 'limit"}}')
        fail_read(nil, nil)
        success_read(nil, "\r\n0\r\n\r\n")
        success_read(nil, nil)
        assert.are.equal('HTTP 400: {"error":{"message":"context limit"}}', failed.err)
        assert.are.same({}, failed.events)
        assert.are.same({ "[DONE]" }, success.events)
        assert.is_nil(success.err)
        assert.are.equal(1, failed.done)
        assert.are.equal(1, success.done)
    end)

    it("shows the status for an empty body and decodes chunked error text", function()
        local empty, read = start()
        read(nil, "HTTP/1.1 503 Unavailable\r\nContent-Length: 0\r\n\r\n")
        read(nil, nil)
        assert.are.equal("HTTP 503", empty.err)
        local chunked, chunk_read = start()
        chunk_read(nil, "HTTP/1.1 400 Bad Request\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nto")
        chunk_read(nil, "o\r\n5\r\n long\r\n0\r\n\r\n")
        chunk_read(nil, nil)
        assert.are.equal("HTTP 400: too long", chunked.err)
    end)
end)
