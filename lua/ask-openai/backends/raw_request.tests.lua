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
    it("v1/chat/completions", function()
        -- do return end
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
            },
            function(sse)
                log:info("sse", ansi.yellow(sse))
            end)

        -- vim.print(data)
        counter:wait(2500)
    end)
end)

-- describe("fork data_only_parser to build on top of raw_request", function()
--     it("", function()
--         -- TODO merge this with my backends/sse/data_only_parser.lua but do so outside of the low level http client I have in raw_request
--     end)
-- end)
