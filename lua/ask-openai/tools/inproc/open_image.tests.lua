require("ask-openai.helpers.test_setup").modify_package_path()
local tool = require("ask-openai.tools.inproc.open_image")
local inprocess = require("ask-openai.tools.inprocess")
local TxChatMessage = require("ask-openai.agents.messages.tx")

describe("open_image", function()
    local files
    before_each(function() files = {} end)
    after_each(function() for _, path in ipairs(files) do vim.uv.fs_unlink(path) end end)
    local function image(data)
        local path = vim.fn.tempname() .. ".not-an-image-extension"
        files[#files + 1] = path
        local file = assert(io.open(path, "wb")); file:write(data); file:close()
        return path
    end
    local function call(args)
        local result
        tool.call(args, function(value) result = value end)
        assert.is_true(vim.wait(1000, function() return result ~= nil end, 5))
        return result
    end

    it("returns an image block through the in-process router and existing multimodal bridge", function()
        local data = vim.base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1kAAAAASUVORK5CYII=")
        local path = image(data)
        local result
        inprocess.send_tool_call({ ["function"] = { name = "open_image", arguments = vim.json.encode({ path = path }) } },
            function(value) result = value end)
        assert.is_true(vim.wait(1000, function() return result ~= nil end, 5))
        assert.is_nil(result.result.isError)
        assert.equals("image", result.result.content[1].type)
        assert.equals("image/png", result.result.content[1].mimeType)
        assert.equals(data, vim.base64.decode(result.result.content[1].data))
        local reply, attachment = TxChatMessage:tool_result({ id = "image-call", call_output = result,
            ["function"] = { name = "open_image" } })
        assert.equals("tool", reply.role)
        assert.is_nil(reply.content:find(result.result.content[1].data, 1, true))
        assert.equals("user", attachment.role)
        assert.equals("image_url", attachment.content[2].type)
        assert.equals("data:image/png;base64," .. vim.base64.encode(data), attachment.content[2].image_url.url)
    end)

    it("recognizes image signatures rather than trusting filename extensions", function()
        for _, case in ipairs({ { "\255\216\255bytes", "image/jpeg" }, { "GIF89a1234", "image/gif" },
            { "RIFF1234WEBPbytes", "image/webp" } }) do
            assert.equals(case[2], call({ path = image(case[1]) }).result.content[1].mimeType)
        end
    end)

    it("returns recoverable errors for missing paths, non-images and directories", function()
        for _, args in ipairs({ {}, { path = "" }, { path = "/this/image/does/not/exist" },
            { path = image("not an image") }, { path = image("") }, { path = vim.fn.getcwd() } }) do
            assert.is_true(call(args).result.isError)
        end
    end)

    it("supports cancellation without returning the image", function()
        local result
        local cancel = tool.call({ path = image("GIF89abytes") }, function(value) result = value end)
        cancel()
        assert.is_true(vim.wait(1000, function() return result ~= nil end, 5))
        assert.equals("open_image cancelled", result.result.content[1].text)
        assert.is_nil(result.result.content[1].data)
    end)
end)
