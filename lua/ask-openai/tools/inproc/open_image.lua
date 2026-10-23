local plumbing = require("ask-openai.tools.plumbing")
local uv = vim.uv or vim.loop
local M = {}

M.ToolDefinition = {
    type = "function",
    ["function"] = {
        name = "open_image",
        description = "View a local image file.",
        parameters = { type = "object", properties = { path = { type = "string" } }, required = { "path" } },
    },
}

local function mime_type(data)
    if data:sub(1, 8) == "\137PNG\r\n\26\n" then return "image/png" end
    if data:sub(1, 3) == "\255\216\255" then return "image/jpeg" end
    if data:sub(1, 6) == "GIF87a" or data:sub(1, 6) == "GIF89a" then return "image/gif" end
    if data:sub(1, 4) == "RIFF" and data:sub(9, 12) == "WEBP" then return "image/webp" end
end

---@type InProcessToolCall
function M.call(args, callback)
    local cancelled, delivered, fd = false, false, nil
    local function finish(data, error_message)
        if fd then uv.fs_close(fd); fd = nil end
        vim.schedule(function()
            if delivered then return end
            delivered = true
            if cancelled then
                callback(plumbing.create_tool_call_output_for_canceled("open_image cancelled"))
            elseif error_message then
                callback(plumbing.create_tool_call_output_for_error_message(error_message))
            else
                local mime = mime_type(data)
                if not mime then
                    callback(plumbing.create_tool_call_output_for_error_message("Expected a PNG, JPEG, GIF or WebP image."))
                    return
                end
                callback(plumbing.create_tool_call_output_for_success({
                    { type = "image", mimeType = mime, data = vim.base64.encode(data) },
                }))
            end
        end)
    end
    if type(args.path) ~= "string" or args.path:match("^%s*$") then
        finish(nil, "path must be a non-empty local file path")
    else
        local path = vim.fn.fnamemodify(args.path, ":p")
        uv.fs_open(path, "r", 0, function(open_error, handle)
            if open_error then finish(nil, "Cannot open image: " .. open_error); return end
            fd = handle
            uv.fs_fstat(fd, function(stat_error, stat)
                if stat_error then finish(nil, "Cannot read image: " .. stat_error); return end
                if cancelled then finish(); return end
                if stat.type ~= "file" or stat.size == 0 then finish(nil, "Expected a non-empty image file."); return end
                if stat.size > 32 * 1024 * 1024 then finish(nil, "Image exceeds 32 MiB; resize it before opening."); return end
                uv.fs_read(fd, stat.size, 0, function(read_error, data)
                    if read_error then finish(nil, "Cannot read image: " .. read_error); return end
                    if #data ~= stat.size then finish(nil, "Image changed while reading; retry opening it."); return end
                    finish(data)
                end)
            end)
        end)
    end
    return function() cancelled = true end
end

return M
