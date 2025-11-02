local messages = require("devtools.messages")
local api = require("ask-openai.api")
local log = require("ask-openai.logs.logger").predictions()

local M = {}

function M.setup()
    M.setup_lsp()
    M.setup_telescope_picker() -- allow testing queries always
end

function M.setup_lsp()
    -- TMP disable, i.e. when working on lsp itself :)
    --  HRMm wont be easy to enable/disable this though, will have to restart if LSP wasn't started and rag is toggled?
    if not api.is_rag_enabled() then
        log:info("NOT starting LSP (b/c RAG is disabled)")
        return
    end


    local lspconfig = require("lspconfig")
    local configs = require("lspconfig.configs")
    local rag_client = require("ask-openai.rag.client")

    if not configs.ask_language_server then
        configs.ask_language_server = {
            default_config = {
                cmd = {
                    os.getenv("HOME") .. "/repos/github/g0t4/ask-openai.nvim/.venv/bin/python",
                    "-m",
                    "lsp.server",
                },
                cmd_cwd = os.getenv("HOME") .. "/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/rag",
                -- filetypes = rag_client.get_filetypes_for_workspace(),
                -- filetypes = { '*' }, -- not set == all filetypes
                --
                -- FYI .git first means repo root is preferred, fallback is CWD
                -- this maps to root_uri/root_path in server's on_initialize
                root_dir = require("lspconfig.util").root_pattern(".git", "."),
            },
        }
    end

    -- vim.lsp.handlers["window/showMessage"] = function(err, result, ctx, config)
    --     messages.append("global handler window/showMessage")
    --     messages.append(vim.inspect(result))
    -- end

    lspconfig.ask_language_server.setup({
        on_attach = function(client, bufnr)
            -- messages.append(client.name .. " is now attached to buffer: " .. bufnr)
            -- messages.ensure_open()
            -- -- messages.append(vim.inspect(client))
            client.handlers = {
                ["fuu/no_dot_rag__do_the_right_thing_wink"] = function(err, result, ctx, config)
                    messages.append("client handler fuu/no_dot_rag__do_the_right_thing_wink")
                    messages.append(vim.inspect(result))
                    -- ask server to shutdown, so I don't ask for more stuff it cannot do!
                    -- WHY THE F does this not request SHUTDOWN!?
                    -- vim.lsp.stop_client(client)
                    -- vim.lsp.stop_client(client)
                end,


                -- ["window/showMessage"] = function(err, result, ctx, config)
                --     messages.append("client handler window/showMessage")
                --     messages.append(vim.inspect(result))
                -- end,
                -- ["window/showMessageRequest"] = function(err, result, ctx, config)
                --     messages.append("client handler window/showMessageRequest")
                --     messages.append(vim.inspect(result))
                -- end,
                -- ["window/logMessage"] = function(err, result, ctx, config)
                --     messages.append("client handler window/logMessage")
                --     messages.append(vim.inspect(result))
                -- end,
            }

            -- vim.defer_fn(function()
            --     local req_id0, cancel0 = vim.lsp.buf_request(0, "workspace/executeCommand", {
            --         command = "SLEEPY",
            --         arguments = { {} }, -- MUST have empty arguments in pygls v2... or set values inside arguments = { { seconds = 10 } },
            --     }, function(err, result)
            --         log:error("DONE error: " .. vim.inspect(err) .. " res:" .. vim.inspect(result))
            --     end)
            --     -- vim.defer_fn(cancel0, 0) -- works fine to cancel all immediately and it does so VERY fast
            --     vim.defer_fn(cancel0, 500)
            --
            --     local req_id1, cancel1 = vim.lsp.buf_request(0, "workspace/executeCommand", {
            --         command = "SLEEPY",
            --         arguments = { { seconds = 10 } },
            --     }, function(err, result)
            --         log:error("DONE error: " .. vim.inspect(err) .. " res:" .. vim.inspect(result))
            --     end)
            --     vim.defer_fn(cancel1, 0)
            --
            --     local req_id2, cancel2 = vim.lsp.buf_request(0, "workspace/executeCommand", {
            --         command = "SLEEPY",
            --         arguments = { { seconds = 10 } },
            --     }, function(err, result)
            --         log:error("DONE error: " .. vim.inspect(err) .. " res:" .. vim.inspect(result))
            --     end)
            --     vim.defer_fn(cancel2, 0)
            -- end, 500)
        end,
    })
end

function on_agg()
    vim.cmd("Telescope ask_semantic_grep languages=ALL")
end

function on_ag()
    vim.cmd("Telescope ask_semantic_grep")
end

function M.setup_telescope_picker()
    require("telescope").load_extension("ask_semantic_grep")

    vim.keymap.set('n', '<leader>ag', on_ag,
        { noremap = true, silent = true, desc = 'Semantic grep Telescope picker, current filetype only' }
    )
    vim.keymap.set('n', '<leader>agg', on_agg,
        { noremap = true, silent = true, desc = 'Semantic grep, Telescope picker, all languages' }
    )
end

return M
