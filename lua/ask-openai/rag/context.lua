local log = require("ask-openai.prediction.logger").predictions()
local files = require("ask-openai.helpers.files")
local M = {}

local cwd = vim.fn.getcwd()
-- only testing ask-openai project currently
local is_rag_indexed_workspace = cwd:find("ask-openai", 1, true) ~= nil

local function fim_concat(prefix, suffix, limit)
    limit = limit or 1500 -- 2000?
    local half = math.floor(limit / 2)

    local short_prefix = prefix:sub(-half)
    local short_suffix = suffix:sub(1, half)

    return short_prefix .. "\n<<<FIM>>>\n" .. short_suffix
end
-- keymap to strigger example hover
vim.keymap.set("n", "<leader>lh", function()
    local params = vim.lsp.util.make_position_params()
    vim.lsp.buf_request(0, "textDocument/hover", params, function(err, result)
        if err then
            vim.notify("LSP error: " .. err.message, vim.log.levels.ERROR)
            return
        end
        if not result then
            vim.notify("No hover information found.", vim.log.levels.WARN)
            return
        end
        local content = result.contents
        -- if vim.islist(content) then
        --     content = vim.lsp.util.convert_doc_links(content, vim.api.nvim_buf_get_name(0))
        -- else
        content = vim.lsp.util.convert_input_to_markdown_lines(content)
        -- end
        -- vim.api.nvim_echo({ { content, "Normal" } }, false, {})
        vim.print(content)
        return vim.lsp.util.open_floating_preview(content, "markdown", { width = 30, height = 2 })
    end)
end, { desc = "LSP Hover", noremap = true })



function M.query_rag_via_lsp(document_prefix, document_suffix, callback)
    if not is_rag_indexed_workspace then
        callback(nil)
        return
    end

    local current_file = files.get_current_file_relative_path()
    local is_lua = current_file:match("%.lua$")
    if not is_lua then
        log:info("skipping RAG for non-lua files: " .. current_file)
        callback(nil)
        return
    end

    local query = fim_concat(document_prefix, document_suffix)
    local message = {
        text = query,
        current_file = current_file,
    }

    vim.lsp.buf_request(0, "workspace/executeCommand", {
        command = "ask.ragQuery",
        -- arguments is an array table, not a dict type table (IOTW only keys are sent if you send a k/v map)
        arguments = { message },
    }, function(err, result)
        if err then
            vim.notify("RAG query failed: " .. err.message, vim.log.levels.ERROR)
            return
        end

        log:info("RAG result:", vim.inspect(result))
        local rag_matches = result.matches or {}
        callback(rag_matches)
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

    local query = fim_concat(document_prefix, document_suffix)
    local message = {
        text = query,
        current_file = files.get_current_file_relative_path(),
    }
    local json = vim.fn.json_encode(message)
    vim.fn.chansend(sock, json .. "\n")
end

return M
