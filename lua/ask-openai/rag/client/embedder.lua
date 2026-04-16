local socket = require("socket")
local cmsgpack = require("cmsgpack")

local M = {}

--- Default connection options – can be overridden via `setup`.
---@type table
local opts = {
    host = "ask.lan",
    port = 8015,
    timeout = 5, -- seconds for connect/read/write
}

--- Configure the client.
--- Allows the caller to set host, port and timeout.
---@param user_opts table
function M.setup(user_opts)
    if type(user_opts) ~= "table" then return end
    for k, v in pairs(user_opts) do
        opts[k] = v
    end
end

--- Internal helper: establish a TCP connection.
---@return socket.tcp|nil, string|nil
local function connect()
    local tcp = assert(socket.tcp())
    tcp:settimeout(opts.timeout)
    local ok, err = tcp:connect(opts.host, opts.port)
    if not ok then
        return nil, ("embeddings connect error: " .. (err or "unknown"))
    end
    return tcp, nil
end

--- Internal helper: send a MessagePack‑encoded request.
---@param tcp socket.tcp
---@param payload table
---@return boolean, string|nil
local function send_message(tcp, payload)
    local data = cmsgpack.pack(payload)
    -- prefix with 4‑byte big‑endian length as expected by the server
    local len = #data
    local prefix = string.char(
        bit.rshift(bit.band(len, 0xFF000000), 24),
        bit.rshift(bit.band(len, 0x00FF0000), 16),
        bit.rshift(bit.band(len, 0x0000FF00), 8),
        bit.band(len, 0x000000FF)
    )
    local ok, err = tcp:send(prefix .. data)
    if not ok then
        return false, ("embeddings send error: " .. (err or "unknown"))
    end
    return true, nil
end

--- Internal helper: receive a length‑prefixed MessagePack response.
---@param tcp socket.tcp
---@return table|nil, string|nil
local function receive_message(tcp)
    local header, err = tcp:receive(4)
    if not header then
        return nil, ("embeddings recv header error: " .. (err or "unknown"))
    end
    local b1, b2, b3, b4 = header:byte(1, 4)
    local len = b1 * 0x1000000 + b2 * 0x10000 + b3 * 0x100 + b4
    local payload, err2 = tcp:receive(len)
    if not payload then
        return nil, ("embeddings recv payload error: " .. (err2 or "unknown"))
    end
    local ok, decoded = pcall(cmsgpack.unpack, payload)
    if not ok then
        return nil, ("embeddings unpack error: " .. (decoded or "unknown"))
    end
    return decoded, nil
end

--- Request an embedding for a single string.
---@param text string
---@return number[]|nil, string|nil
function M.embed_text(text)
    if type(text) ~= "string" then
        return nil, "embed_text expects a string"
    end
    local tcp, err = connect()
    if not tcp then return nil, err end
    local ok, send_err = send_message(tcp, { text = text })
    if not ok then return nil, send_err end
    local resp, recv_err = receive_message(tcp)
    tcp:close()
    if not resp then return nil, recv_err end
    if resp.error then return nil, resp.error end
    return resp.embeddings, nil
end

--- Request embeddings for a batch of strings, splitting into sub‑batches when needed.
---@param texts string[] @list of strings to embed
---@param batch_size? integer @size of each sub‑batch (default 8)
---@return table[]|nil, string|nil @list of embedding vectors or error message
function M.embed_batch(texts, batch_size)
    batch_size = batch_size or 8

    if type(texts) ~= "table" then
        return nil, "embed_batch expects a table of strings"
    end

    local total = #texts
    local all_vecs = {}

    for i = 1, total, batch_size do
        local batch_end = math.min(i + batch_size - 1, total)
        local batch = {}
        for j = i, batch_end do
            table.insert(batch, texts[j])
        end

        vim.print(string.format("batch %d-%d of %d", i, batch_end, total))

        -- Open a new connection for each sub‑batch
        local tcp, err = connect()
        if not tcp then
            vim.print("  TCP.connect ", vim.inspect(tcp), vim.inspect(err))
            return nil, err
        end

        local ok, send_err = send_message(tcp, { batch = batch })
        if not ok then
            vim.print("  send_message error: ", vim.inspect(ok), vim.inspect(send_err))
            tcp:close()
            return nil, send_err
        end

        local resp, recv_err = receive_message(tcp)
        tcp:close()
        if not resp then
            vim.print("  receive_message error: ", vim.inspect(recv_err))
            return nil, recv_err
        end
        if resp.error then
            vim.print("  embed_batch error: ", vim.inspect(resp.error))
            return nil, resp.error
        end

        table.insert(all_vecs, resp.embeddings)
    end

    -- Concatenate results from all sub‑batches
    local concatenated = {}
    for _, vecs in ipairs(all_vecs) do
        for _, v in ipairs(vecs) do
            table.insert(concatenated, v)
        end
    end

    return concatenated, nil
end

function M.qwen3_format_query(query, instruct)
    if instruct ~= nil then
        -- FYI verbatim copy of formatter from embedder.py...
        --   was the lack of " " after Query: in the original examples?
        return "Instruct: " .. instruct .. "\nQuery:" .. query
    end
    return "Query: " .. query
end

return M
