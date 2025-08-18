-- telescope deps:
local actions = require('telescope.actions')
local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local sorters = require('telescope.sorters')
local previewers = require('telescope.previewers')
local messages = require('devtools.messages')
local telescope_config = require('telescope.config').values
local make_entry = require('telescope.make_entry')
local state = require('telescope.actions.state')
-- non-telescope deps:
local files = require("ask-openai.helpers.files")

local even_sorter = sorters.Sorter:new {
    scoring_function = function(_, prompt, entry)
        messages.ensure_open()
        messages.append("called sorter: " .. vim.inspect(prompt))
        messages.append("called sorter: " .. vim.inspect(entry))
        -- Always keep every entry, score doesn't matter
        return 1
    end,
    highlighter = function(_, prompt, display)
        messages.ensure_open()
        messages.append("called highlighter: " .. vim.inspect(prompt))
        messages.append("called highlighter: " .. vim.inspect(display))
        -- No highlights
        return {}
    end,
}

local Latest = { gen = 0, proc = nil, lsp = nil, req = nil }

function Latest:start_job(cmd, on_done)
    self.gen = self.gen + 1
    local gen = self.gen
    if self.proc and not self.proc:is_closing() then pcall(self.proc.kill, self.proc, 2) end -- SIGINT
    self.proc = vim.system(cmd, { text = true }, function(res)
        if gen ~= self.gen then return end -- drop stale result
        on_done(res)
    end)
end

function Latest:start_lsp(client, method, params, on_done)
    self.gen = self.gen + 1
    local gen = self.gen
    if self.lsp and self.req then pcall(self.lsp.cancel_request, self.lsp, self.req) end
    self.lsp = client
    local ok, req = client.request(method, params, function(err, result)
        if gen ~= self.gen then return end -- drop stale result
        on_done(err, result)
    end)
    if ok then self.req = req end
end

local _telescope_find_callable_obj = function()
    local obj = {}

    obj.__index = obj
    obj.__call = function(t, ...)
        return t:_find(...)
    end

    obj.close = function() end

    return obj
end

local AsyncDynamicFinder = _telescope_find_callable_obj()

function AsyncDynamicFinder:new(opts)
    opts = opts or {}

    assert(not opts.results, "`results` should be used with finder.new_table")
    assert(not opts.static, "`static` should be used with finder.new_oneshot_job")

    local obj = setmetatable({
        curr_buf = opts.curr_buf,
        fn = opts.fn,
        entry_maker = opts.entry_maker or make_entry.gen_from_string(opts),
    }, self)

    return obj
end

function AsyncDynamicFinder:_find(prompt, process_result, process_complete)
    -- I adapted this from DyanmicFinder... all of this is so stupidly named
    self.fn(prompt, process_result, process_complete, self.entry_maker)

    -- local result_num = 0
    -- for _, result in ipairs(results) do
    --     result_num = result_num + 1
    --     local entry = self.entry_maker(result)
    --     if entry then
    --         entry.index = result_num
    --     end
    --     if process_result(entry) then
    --         return
    --     end
    -- end
    --
    -- process_complete()
end

local client_request_ids, cancel_all_requests
function _context_query_sync(message, lsp_buffer_number, process_result, process_complete, entry_maker)
    if cancel_all_requests then
        cancel_all_requests()
    end

    messages.header("context query")
    -- messages.append("message" .. vim.inspect(message))
    -- messages.append("lsp_buffer_number" .. lsp_buffer_number)
    lsp_buffer_number = lsp_buffer_number or 0


    -- message.text = "setmantic_grep" -- TODO remove later
    -- TODO refine instructions
    message.instruct = "Semantic grep of relevant code for display in neovim, using semantic_grep extension to telescope"
    -- current_file_absolute_path  -- PRN default?
    -- vim_filetype  -- PRN default?

    -- TODO see my _context_query for ASYNC example once I am done w/ sync testing
    -- I should be able to stream in results
    -- TODO handle canceling previous query on next one!
    -- in telescope can I have the user type in a prompt and decide when to execute it?
    --  or is it live search only?

    client_request_ids, cancel_all_requests = vim.lsp.buf_request(lsp_buffer_number, "workspace/executeCommand", {
            command = "context.query",
            arguments = { message },
        },
        function(err, result, ctx)
            if err then
                messages.append("context query failed: " .. err.message)
                return {}
            end

            -- messages.append("result: " .. vim.inspect(result))
            if not result then
                messages.append("failed to get results")
                return {}
            end
            local matches = result.matches or {}
            for i, match in ipairs(matches) do
                -- messages.append("match: " .. vim.inspect(match))
                local entry = entry_maker(match)
                entry.index = i -- NOTE this is different than normal telescope!
                process_result(entry)
            end
            process_complete()
        end
    )
end

local termopen_previewer_bat = previewers.new_termopen_previewer({
    -- FYI this will have race condition issues on setting cursor position too...
    get_command = function(entry)
        match = entry.match
        -- messages.append("entry: " .. vim.inspect(match))

        local f = match.file
        local cmd = {
            "bat",
            "--paging=never",
            "--color=always",
            -- "--style=plain",
            "--number",
            "--line-range", string.format("%d:%d", math.max(1, match.start_line - 10), math.max(1, match.end_line + 10)), -- context
            -- "--line-range", string.format("%d:%d", 1, 10),
            "--highlight-line", string.format("%d:%d", match.start_line, match.end_line),
            f,
        }
        return cmd
    end,
})

local ns = vim.api.nvim_create_namespace("rag_preview")
-- -- I want my own highlight style (not Search)
local hlgroup = "RagLineRange"
vim.api.nvim_set_hl(0, hlgroup, {
    -- bg = "#50fa7b",
    bg = "#414858",
    -- bold = true,
    -- standout = true,
})

local custom_buffer_previewer = previewers.new_buffer_previewer({
    define_preview = function(self, entry)
        local filename = entry.path or entry.filename
        local winid = self.state.winid
        local bufnr = self.state.bufnr

        vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.fn.readfile(filename))
        vim.api.nvim_buf_set_option(bufnr, "modifiable", false)

        local num_lines = vim.api.nvim_buf_line_count(bufnr)
        -- messages.append("file: " .. filename .. ", num_lines: " .. num_lines)
        -- messages.append("entry: " .. vim.inspect(entry))

        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
        local start_line, end_line = entry.match.start_line, entry.match.end_line -- 1-based
        -- messages.append("start_line, e: " .. start_line .. ", " .. end_line)
        -- messages.append("winid = " .. winid)

        for l = start_line - 1, end_line - 1 do
            vim.api.nvim_buf_add_highlight(bufnr, ns, "RagLineRange", l, 0, -1)
        end

        local ft = vim.filetype.match({ filename = filename }) or "text"
        vim.bo[bufnr].filetype = ft -- triggers FileType autocommands
        vim.bo[bufnr].syntax = "" -- avoid regex syntax if you only want TS
        -- require('telescope.previewers.utils').highlighter(bufnr, ft)

        Latest.gen = Latest.gen + 1
        local gen = Latest.gen
        vim.schedule(function()
            if gen ~= Latest.gen then
                return
            end
            if not vim.api.nvim_win_is_valid(winid) then
                return
            end
            if not vim.api.nvim_buf_is_loaded(bufnr) then
                -- if no buffer found or not loaded, then abort
                return
            end
            -- messages.append("winid = " .. winid .. ", bufnr = " .. bufnr .. ", ns = " .. ns .. ", lnum = " .. lnum)

            vim.api.nvim_win_call(winid, function()
                pcall(vim.api.nvim_win_set_cursor, winid, { start_line, 0 })
                vim.cmd('normal! zz') -- center like `zz`
            end)
        end)
    end,
})


local function semantic_grep_current_filetype_picker(opts)
    -- GOOD examples (multiple pickers in one nvim plugin):
    --  https://gitlab.com/davvid/telescope-git-grep.nvim/-/blob/main/lua/git_grep/init.lua?ref_type=heads

    -- TODO! show columns, with score too... basename on file? or some util to truncate?
    -- TODO! cancel previous queries? async too so not locking up UI?

    -- * this runs before picker opens, so you can gather context, i.e. current filetype, its LSP, etc
    -- messages.append("opts" .. vim.inspect(opts))
    local query_args = {
        -- TODO should I have one picker that is specific to current file type only
        --  and then another that searches code across all filetypes?
        --  use re-ranker in latter case!
        filetype = vim.o.filetype,
        current_file_absolute_path = files.get_current_file_absolute_path(),
    }
    -- messages.append("query_args:", vim.inspect(query_args))
    local lsp_buffer_number = vim.api.nvim_get_current_buf()

    opts_previewer = {}
    pickers.new({ opts }, {
        prompt_title = 'semantic grep - for testing RAG queries',


        finder = AsyncDynamicFinder:new({
            fn = function(prompt, process_result, process_complete, entry_maker)
                if not prompt or prompt == '' then
                    return {}
                end

                -- function is called each time the user changes the prompt (text in the Telescope Picker)
                query_args.text = prompt
                -- TODO make async query instead using buf_request instead of buf_request_sync
                return _context_query_sync(query_args, lsp_buffer_number, process_result, process_complete, entry_maker)
            end,
            entry_maker = function(match)
                -- FYI `:h telescope.make_entry`
                -- `:h telescope.pickers.entry_display` -- TODO?

                -- * match example
                --     end_line = 87,
                --     file = "<ABS PATH>"
                --     rank = 2,
                --     score = 0.71245551109314,
                --     start_line = 76,
                --     text = "\nfunction M.setup_telescope_picker()\n...",
                --     type = "lines"

                -- FYI would really be cool if I start to use treesitter for RAG chunking cuz then likely the first line will have the name of a function or otherwise!
                -- lift out first function nameoanywhere in lines?
                -- fallback to first line/last line parts
                display_first_line = match.text.sub(match.text, 1, 20)
                display_last_line = match.text.sub(match.text, -20, -1)
                display = display_first_line .. "..." .. display_last_line

                ordinal = match.text
                -- ordinal = match.score -- TODO can I use numeric score?

                return {
                    value = match,
                    -- valid = false -- hide it (also can return nil for entire object)
                    display = display, -- string|function
                    ordinal = ordinal, -- for filtering

                    -- default action uses these to jump to file location
                    filename = match.file,
                    lnum = match.start_line,
                    -- col = 0

                    match = match, -- TODO can I add extra details?
                }
                -- optional second return value
            end,
        }),

        -- :h telescope.previewers
        -- previewer = require('telescope.config').values.grep_previewer(opts_previewer), -- show filename/path + jump to lnum
        -- previewer = termopen_previewer_bat,
        previewer = custom_buffer_previewer,
        -- previewer = false, -- no preview

        sorter = sorters.get_generic_fuzzy_sorter(),
        attach_mappings = function(prompt_bufnr, keymap)
            -- actions.select_default:replace(function()
            --     -- actions.close(prompt_bufnr)
            --     local selection = state.get_selected_entry()
            --     -- TODO jump to start line of match
            --     -- vim.api.nvim_command('vsplit ' .. link)
            -- end)
            -- keymap({ 'n' }, 'c', function()
            --     -- add to context
            --     -- TODO add action for adding to an explicit context!
            --     -- TODO it would also be useful to have add to explicit context on a regular rg file search
            -- end)
            return true
        end,
    }):find()
end

return require('telescope').register_extension {
    -- PRN setup
    exports = {
        ask_semantic_grep = semantic_grep_current_filetype_picker,
        -- PRN other pickers!
    },
}
