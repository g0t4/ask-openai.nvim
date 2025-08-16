local messages = require("devtools.messages")
local api = require("ask-openai.api")
local log = require("ask-openai.logs.logger").predictions()

local M = {}

function M.setup()
    M.setup_telescope_picker() -- allow testing queries always

    -- TMP disable, i.e. when working on lsp itself :)
    --  HRMm wont be easy to enable/disable this though, will have to restart if LSP wasn't started and rag is toggled?
    if not api.is_rag_enabled() then
        log:info("NOT starting LSP (b/c RAG is disabled)")
        return
    end


    local lspconfig = require("lspconfig")
    local configs = require("lspconfig.configs")

    if not configs.ask_language_server then
        configs.ask_language_server = {
            default_config = {
                cmd = {
                    os.getenv("HOME") .. "/repos/github/g0t4/ask-openai.nvim/.venv/bin/python",
                    "-m",
                    "lsp.server",
                },
                cmd_cwd = os.getenv("HOME") .. "/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/rag",
                filetypes = { "lua", "python", "fish" },
                -- filetypes = { "lua" }, -- USE this if python is too busy while you are writing code for LS!
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
        end,
    })
end

function M.setup_telescope_picker()
    require("telescope").load_extension("ask_semantic_grep")

    vim.keymap.set('n', '<leader>ag', ':<Cmd>Telescope ask_semantic_grep<CR>',
        { noremap = true, silent = true, desc = 'Ask semantic grep (RAG test)' }
    )
end

return M
