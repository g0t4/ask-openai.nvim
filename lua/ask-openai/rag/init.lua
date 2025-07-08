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
                filetypes = { "lua" },
                root_dir = require("lspconfig.util").root_pattern(".git", "."),

            },
        }
    end

    lspconfig.ask_language_server.setup({})
end

return M
