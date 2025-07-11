local messages = require("devtools.messages")

local M = {}

function M.setup()
    -- do return end
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
                    vim.lsp.stop_client(client)
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

return M
