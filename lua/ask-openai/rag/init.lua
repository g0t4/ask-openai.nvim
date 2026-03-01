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
        log:trace("NOT starting LSP (b/c RAG is toggled off)")
        return
    end
    local rag_client = require("ask-openai.rag.client")
    if not rag_client.is_rag_supported() then
        log:error("NOT starting LSP for RAG")
        return
    end

    -- TODO detect initial failure to start LSP => stop trying... so when embeddings server is down
    --  FYI see rag_client.is_rag_supported_in_current_file() for ideas
    --  maybe even set some failure flag from initial setup here (or in a callback)

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
        local root = vim.fs.root(filepath, {
            ".rag", -- only if a .rag dir, otherwise we don't start this LS
            -- FYI might have issues w/ nested .rag dirs but I don't really use that... handle if it arises
            -- ".git", -- common, but in my case I need .rag (in fact, LS should never be setup if there's no .rag dir, so this would never be called)
        })

        -- TODO comment out logs once you are comfortable w/ migration to vim.lsp.config
        if root then
            -- ONLY start LS if you find a root
            log:info(string.format("found ask-LS root=%s, bufnr=%d %s", tostring(root), bufnr, filepath))
            on_dir(root)
            return
        end
        log:warn(string.format("no ask-LS root found for bufnr=%d %s", bufnr, filepath))
    end

    vim.lsp.config("ask_language_server", {

        -- * language server
        cmd = {
            os.getenv("HOME") .. "/repos/github/g0t4/ask-openai.nvim/.venv/bin/python",
            "-m",
            "lsp.server",
        },
        cmd_cwd = os.getenv("HOME") .. "/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/rag",

        -- old values from lspconfig setup => these might need adjusted if filetypes differs in vim.lsp.config
        -- filetypes = rag_client.get_filetypes_for_workspace(),
        -- filetypes = { '*' }, -- not set == all filetypes

        root_dir = root_dir
    })
    -- log:info(vim.inspect(vim.lsp.config))

    -- FYI troubleshooting:
    -- - :checkhealth vim.lsp  # shows enabled vs active (buffer #s too)

    vim.lsp.enable("ask_language_server")

    ---@param result { message: string, type: number }  -- Language Server MessageType
    local function map_lsp_level_to_vim_level(result)
        local level_map = {
            [1] = vim.log.levels.ERROR, -- MessageType.Error
            [2] = vim.log.levels.WARN, -- MessageType.Warning
            [3] = vim.log.levels.INFO, -- MessageType.Info
            [5] = vim.log.levels.DEBUG, -- MessageType.Debug
            [4] = vim.log.levels.TRACE, -- MessageType.Log => not sure Log == Trace but meh!
        }
        return level_map[result.type] or vim.log.levels.INFO
    end
    -- global handler
    vim.lsp.handlers["window/showMessage"] = function(err, result, ctx, config)
        log:info("global handler window/showMessage", vim.inspect(result))
        vim.notify(result.message, map_lsp_level_to_vim_level(result))
    end


    --- @alias EventArgs { id:number, event: string, group: number|nil, file: string, match: string, buf:number, data: table }

    -- if LS provides dynamic registration, then some capabilities aren't registered until after LspAttach event
    vim.lsp.handlers['client/registerCapability'] = (function(overridden)
        -- see :h LspAttach
        return function(err, res, ctx)
            -- TODO if I don't have this in my LS then comment out this handler
            log:info(string.format("client/registerCapability: client_id=%s", ctx.client_id))
            local result = overridden(err, res, ctx)
            local client = vim.lsp.get_client_by_id(ctx.client_id)
            if not client or client.name ~= "ask_language_server" then return end

            for bufnr, _ in pairs(client.attached_buffers) do
                -- Call your custom on_attach logic...
                -- my_on_attach(client, bufnr)
            end
            return result
        end
    end)(vim.lsp.handlers['client/registerCapability'])

    vim.api.nvim_create_autocmd('LspDetach', {
        callback =
        --- @param event_args EventArgs
            function(event_args)
                log:info(string.format("LspDetach: client_id=%s (buf %d)", event_args.data.client_id, event_args.buf))
                local client = vim.lsp.get_client_by_id(event_args.data.client_id)
                if not client or client.name ~= "ask_language_server" then return end


                -- Remove the autocommand to format the buffer on save, if it exists
                if client:supports_method('textDocument/formatting') then
                    vim.api.nvim_clear_autocmds({
                        event = 'BufWritePre',
                        buffer = event_args.buf,
                    })
                end
            end,
    })

    vim.api.nvim_create_autocmd('LspAttach', {
        callback =
        --- @param event_args EventArgs
            function(event_args)
                log:info(string.format("LspAttach: client_id=%s (buf %d)", event_args.data.client_id, event_args.buf))
                local client = vim.lsp.get_client_by_id(event_args.data.client_id)
                if not client or client.name ~= "ask_language_server" then return end

                log:info("Server capabilities:", vim.inspect(client.server_capabilities))

                client.handlers = {
                    ["fuu/no_dot_rag__do_the_right_thing_wink"] = function(err, result, ctx, config)
                        log:info("client handler fuu/no_dot_rag__do_the_right_thing_wink", vim.inspect(result))
                        -- ask server to shutdown, so I don't ask for more stuff it cannot do!
                        -- WHY THE F does this not request SHUTDOWN!?
                        -- vim.lsp.stop_client(client)
                        -- vim.lsp.stop_client(client)
                    end,
                    -- ["window/showMessage"] = function(err, result, ctx, config)
                    --     log:info("client handler window/showMessage")
                    --     log:info(vim.inspect(result))
                    -- end,
                    -- ["window/showMessageRequest"] = function(err, result, ctx, config)
                    --     log:info("client handler window/showMessageRequest")
                    --     log:info(vim.inspect(result))
                    -- end,
                    -- ["window/logMessage"] = function(err, result, ctx, config)
                    --     log:info("client handler window/logMessage")
                    --     log:info(vim.inspect(result))
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
            end
    })
end

function on_agg()
    vim.cmd("Telescope ask_semantic_grep languages=GLOBAL")
end

function on_age()
    vim.cmd("Telescope ask_semantic_grep languages=EVERYTHING")
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
        { noremap = true, silent = true, desc = 'Semantic grep, Telescope picker, global languages (subject to rag.yaml -> global_languages)' }
    )
    vim.keymap.set('n', '<leader>age', on_age,
        { noremap = true, silent = true, desc = 'Semantic grep, Telescope picker, everything (NOT subject to rag.yaml -> global_languages)' }
    )
end

return M
