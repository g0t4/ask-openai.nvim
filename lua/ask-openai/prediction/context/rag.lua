local log = require("ask-openai.prediction.logger").predictions()
local M = {}

function M.query_rag_first(document_prefix, document_suffix, callback)
    local sock = vim.fn.sockconnect("tcp", "localhost:9999", {
        on_data = function(_, data)
            -- TODO how do I ensure ONLY one response?!
            --  I am getting multiple on_data callbacks... last one is empty though?
            if data == nil then
                log:info("nil data, aborting...")
                return
            end
            log:info("raw data", vim.inspect(data))
            data = table.concat(data, "\n")
            if data ~= "" then
                local response = vim.fn.json_decode(data)
                local rag_matches = response.matches or {}
                log:trace("rag_matches", vim.inspect(rag_matches))
                callback(rag_matches)
            end
        end,
        rpc = false,
    })

    local function safe_concat(prefix, suffix, limit)
        limit = limit or 1500 -- 2000?
        local half = math.floor(limit / 2)

        local short_prefix = prefix:sub(-half)
        local short_suffix = suffix:sub(1, half)

        return short_prefix .. "\n<<<FIM>>>\n" .. short_suffix
    end

    local query = safe_concat(document_prefix, document_suffix)
    local message = { text = query }
    local json = vim.fn.json_encode(message)
    vim.fn.chansend(sock, json .. "\n")
end

return M
