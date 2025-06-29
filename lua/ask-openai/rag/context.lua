local log = require("ask-openai.prediction.logger").predictions()
local files = require("ask-openai.helpers.files")
local M = {}

local cwd = vim.fn.getcwd()
-- only testing ask-openai project currently
local is_rag_indexed_workspace = cwd:find("ask-openai", 1, true) ~= nil

function M.query_rag_via_lsp(document_prefix, document_suffix, callback)
    vim.lsp.buf_request(0, "workspace/executeCommand", {
        command = "ask.ragQuery",
        arguments = { "my input here" },
    }, function(err, result)
        if err then
            vim.notify("RAG query failed: " .. err.message, vim.log.levels.ERROR)
            return
        end
        print("RAG result:", vim.inspect(result))
        callback(nil)
    end)
end

function M.query_rag_first(document_prefix, document_suffix, callback)
    if not is_rag_indexed_workspace then
        callback(nil)
        return
    end

    local sock
    sock = vim.fn.sockconnect("tcp", "localhost:9999", {
        on_data = function(_, data)
            if data == nil then
                log:info("nil data, aborting...")
                return
            end
            -- log:info("raw rag response", vim.inspect(data))
            data = table.concat(data, "\n")
            if data == "" then
                -- TODO verify if emtpy indeed is when I want to close the socket?
                --   I've always received it last, but I can't find docs about on_data to find out when its called
                --   i.e. is "" a signal that the server disconnected?
                log:info("empty data, closing socket...")
                vim.fn.chanclose(sock)
                return
            end
            local response = vim.fn.json_decode(data)
            local rag_matches = response.matches or {}
            -- log:trace("rag_matches", vim.inspect(rag_matches))
            callback(rag_matches)
        end,
        rpc = false,
    })

    local function fim_concat(prefix, suffix, limit)
        limit = limit or 1500 -- 2000?
        local half = math.floor(limit / 2)

        local short_prefix = prefix:sub(-half)
        local short_suffix = suffix:sub(1, half)

        return short_prefix .. "\n<<<FIM>>>\n" .. short_suffix
    end

    local query = fim_concat(document_prefix, document_suffix)
    local message = {
        text = query,
        current_file = files.get_current_file_relative_path(),
    }
    local json = vim.fn.json_encode(message)
    vim.fn.chansend(sock, json .. "\n")
end

return M
