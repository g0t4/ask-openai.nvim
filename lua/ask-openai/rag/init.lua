local messages = require("devtools.messages")
local log = require("devtools.logs.logger").universal()
local rag_client = require("ask-openai.rag.client")
local config = require("ask-openai.config")

local M = {}

function M.setup()
    M.setup_vim_lsp()
    M.setup_telescope_picker() -- allow testing queries always
end

function M.setup_vim_lsp()
    if not config.is_rag_enabled() then
        log:trace("NOT starting LSP - RAG is OFF")
        return
    end
    if not rag_client.is_rag_supported() then
        log:error("NOT starting LSP - RAG is NOT SUPPORTED")
        return
    end

    --- @param bufnr number
    --- @param on_dir fun(string)
    local function root_dir(bufnr, on_dir)
        -- NOTES:
        -- - FYI vim.lsp.config's root_dir func is NOT compatible with nvim-lspconfig's root_dir func
        -- - DO not use `root_marker` b/c it will start LSP with root_uri=None if it doesn't find the root marker! (YIKES)
        -- - use this `root_dir` function and just don't call `on_dir` if you don't want the LS for a given file
        -- - finds workspace root for *EACH BUFFER*
        --   - each root discovered == new LS instance (makes sense)
        --   - thus, F12 into a library => opens a separate LS instance for the library (also makes sense)
        --     - if library has its own RAG indexes => well, you might want to search those!

        -- * get root based on first .rag dir in/above file's directory
        local filepath = vim.api.nvim_buf_get_name(bufnr)
        local rag_root_dir = vim.fs.root(filepath, {
            ".rag", -- only if a .rag dir, otherwise we don't start this LS
            -- FYI might have issues w/ nested .rag dirs but I don't really use that... handle if it arises
            -- ".git", -- common, but in my case I need .rag (in fact, LS should never be setup if there's no .rag dir, so this would never be called)
        })

        if not rag_root_dir then
            log:warn(string.format("no ask-LS root found for bufnr=%d %s", bufnr, filepath))
            return
        end
        local cwd = vim.fn.getcwd()
        local is_file_in_cwd = filepath:sub(1, #cwd) == cwd
        -- FYI! if you see RAG results seemingly coming from a different repo, use this log to check located root:
        if is_file_in_cwd then
            -- log:info(string.format("found ask-LS rag_root_dir=%s, bufnr=%d %s", tostring(rag_root_dir), bufnr, filepath))
        else
            -- just means you are using an index from another repo, not a bad thing actually!
            --  i.e. if I drill into a dependency and want to search its RAG index... this is a good thing!
            --  but it can catch me off guard when I don't realize I have a file from another repo open
            log:warn(string.format(
                "ask-LS starting for files in a different repo/workspace"
                .. "\n  cwd      = %s"
                .. "\n  filepath = %s" .. " (bufnr=%d)"
                .. "\n  rag_root = %s"
                , cwd, filepath, bufnr, rag_root_dir))
            -- FYI show filepath before rag_root_dir b/c former "selects" later
        end
        -- ONLY start LS if you find a rag_root_dir
        on_dir(rag_root_dir)
    end

    vim.lsp.config("ask_ls", {

        -- * language server
        cmd = {
            os.getenv("HOME") .. "/repos/github/g0t4/ask-openai.nvim/.venv/bin/python",
            "-m",
            "language_server",
        },
        cmd_cwd = os.getenv("HOME") .. "/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/rag",

        -- old values from lspconfig setup => these might need adjusted if filetypes differs in vim.lsp.config
        -- filetypes = rag_client.get_filetypes_for_workspace(),
        -- not set == all filetypes
        -- DO NOT SET filetypes = { '*' }, -- doesn't work

        root_dir = root_dir
    })

    vim.lsp.enable("ask_ls")

    --- @alias EventArgs { id:number, event: string, group: number|nil, file: string, match: string, buf:number, data: table }

    vim.api.nvim_create_autocmd('LspDetach', {
        callback =
        --- @param event_args EventArgs
            function(event_args)
                log:info(string.format("LspDetach: client_id=%s (buf %d)", event_args.data.client_id, event_args.buf))
                local client = vim.lsp.get_client_by_id(event_args.data.client_id)
                if not client or client.name ~= "ask_ls" then return end

                -- PRN remove keymaps (if added in LspAttach)
                -- -- Remove the autocommand to format the buffer on save, if it exists
                -- if client:supports_method('textDocument/formatting') then
                --     vim.api.nvim_clear_autocmds({
                --         event = 'BufWritePre',
                --         buffer = event_args.buf,
                --     })
                -- end
            end,
    })

    vim.api.nvim_create_autocmd('LspAttach', {
        callback =
        --- @param event_args EventArgs
            function(event_args)
                -- log:info(string.format("LspAttach: client_id=%s (buf %d)", event_args.data.client_id, event_args.buf))
                local client = vim.lsp.get_client_by_id(event_args.data.client_id)
                if not client or client.name ~= "ask_ls" then return end

                -- Log server capabilities only once per client to avoid noisy output
                -- if not client._asked_openai_capabilities_logged then
                --     log:info("Server capabilities:", vim.inspect(client.server_capabilities))
                --     client._asked_openai_capabilities_logged = true
                -- end

                ---@type lsp.Handler
                function window_showMessage(err, result, ctx, config)
                    log:info("ask_ls window/showMessage", result)
                    vim.notify(result)
                end

                ---@type lsp.Handler
                function window_logMessage(err, result, ctx, config)
                    log:info("ask_ls window/logMessage", result)
                end

                client.handlers = {
                    ["fuu/no_dot_rag__do_the_right_thing_wink"] = function(err, result, ctx, config)
                        log:info("client handler fuu/no_dot_rag__do_the_right_thing_wink", vim.inspect(result))
                        -- ask server to shutdown, so I don't ask for more stuff it cannot do!
                        -- WHY THE F does this not request SHUTDOWN!?
                        -- vim.lsp.stop_client(client)
                    end,
                    ["window/showMessage"] = window_showMessage,
                    -- ["window/showMessageRequest"] = function(err, result, ctx, config)
                    --     log:info("client handler window/showMessageRequest")
                    --     log:info(vim.inspect(result))
                    -- end,
                    ["window/logMessage"] = window_logMessage,
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
            end
    })
end

--- Checks if semantic grep is available for the current session.
--- @return boolean is_available
--- @return string? warning_message
local function is_semantic_grep_available()
    local rag_is_enabled = config.is_rag_enabled()
    local rag_is_supported = rag_client.is_rag_supported()

    if not rag_is_enabled then
        return false, "RAG is disabled. Enable it to use semantic grep."
    end

    if not rag_is_supported then
        return false, "RAG server is not available. Start the LSP server to use semantic grep."
    end

    return true
end

--- Opens the semantic grep Telescope picker with the given command.
--- Shows a warning if RAG is not available.
--- @param cmd string The telescope command to execute (e.g., "Telescope ask_semantic_grep domains=GLOBAL")
local function open_semantic_grep_picker(cmd)
    local is_available, warning_message = is_semantic_grep_available()
    if not is_available then
        vim.notify(warning_message, vim.log.levels.WARN)
        return
    end
    vim.cmd(cmd)
end

function on_agg()
    open_semantic_grep_picker("Telescope ask_semantic_grep domains=GLOBAL")
end

function on_age()
    open_semantic_grep_picker("Telescope ask_semantic_grep domains=EVERYTHING")
end

function on_ag()
    open_semantic_grep_picker("Telescope ask_semantic_grep")
end

function M.setup_telescope_picker()
    require("telescope").load_extension("ask_semantic_grep")

    vim.keymap.set('n', '<leader>ag', on_ag,
        { noremap = true, silent = true, desc = 'Semantic grep Telescope picker, current filetype only' }
    )
    vim.keymap.set('n', '<leader>agg', on_agg,
        { noremap = true, silent = true, desc = 'Semantic grep, Telescope picker, global domains (subject to rag.yaml -> global_domains)' }
    )
    vim.keymap.set('n', '<leader>age', on_age,
        { noremap = true, silent = true, desc = 'Semantic grep, Telescope picker, everything (NOT subject to rag.yaml -> global_domains)' }
    )
end

return M
