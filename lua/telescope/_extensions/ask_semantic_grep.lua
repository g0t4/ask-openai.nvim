-- telescope deps:
local actions = require('telescope.actions')
local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local entry_display = require "telescope.pickers.entry_display"
local utils = require('telescope.utils') -- to use as a dependency, see https://github.com/nvim-telescope/telescope.nvim/blob/271832a170502dbd92b29fc67755098d8b09838a/lua/telescope/utils.lua#L235
local sorters = require('telescope.sorters')
local previewers = require('telescope.previewers')
local state = require('telescope.actions.state')
-- non-telescope deps:
local files = require("ask-openai.helpers.files")
local logs = require('ask-openai.logs.logger').predictions()
local AsyncDynamicFinder = require('telescope._extensions.ask_semantic_grep.async_dynamic_finder')

local latest_query_num = 0
local picker

local client_request_ids, cancel_all_requests


---@param lsp_rag_request LSPRagQueryRequest
---@param lsp_buffer_number integer
---@param process_result fun(entry: SemanticGrepTelescopeEntryMatch)
---@param process_complete fun()
---@param entry_maker fun(match: LSPRankedMatch): SemanticGrepTelescopeEntryMatch
function _semantic_grep(lsp_rag_request, lsp_buffer_number, process_result, process_complete, entry_maker)
    if cancel_all_requests then
        logs:info("canceling previous request")
        cancel_all_requests()
    end

    lsp_buffer_number = lsp_buffer_number or 0

    -- * instruct
    -- FYI! sync any changes to instruct to the respective python re-ranking code
    lsp_rag_request.instruct = "Semantic grep of relevant code for display in neovim, using semantic_grep extension to telescope" -- * first instruct, well performing with embeddings alone!
    --
    -- TODO try this instead after I geet a feel for re-rank with my original instruct:
    --   instruct_aka_task = "Given a user Query to find code in a repository, retrieve the most relevant Documents"
    --   PRN tweak/evaluate performance of different instruct/task descriptions?

    client_request_ids, cancel_all_requests = vim.lsp.buf_request(lsp_buffer_number, "workspace/executeCommand", {
            command = "semantic_grep",
            arguments = { lsp_rag_request },
        },
        ---@param result LSPRagQueryResult
        function(err, result, ctx)
            -- logs:info("semantic_grep callback: " .. vim.inspect({ err = err, result = result, ctx = ctx }))

            if err then
                logs:error("semantic_grep failed: " .. err.message)
                return {}
            end

            -- logs:info("result: " .. vim.inspect(result))
            if not result then
                logs:error("semantic_grep failed to get results")
                return {}
            end

            local matches = result.matches or {}
            for i, match in ipairs(matches) do
                -- logs:info("match: " .. vim.inspect(match))
                local entry = entry_maker(match)
                process_result(entry)
            end
            -- logs:info("picker: " .. vim.inspect(picker))

            -- picker.max_results = 10
            process_complete()

            cancel_all_requests = nil
            client_request_ids = nil
        end
    )
end

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

    ---@param entry SemanticGrepTelescopeEntryMatch
    define_preview = function(self, entry)
        local filename = entry.filename
        local winid = self.state.winid
        local bufnr = self.state.bufnr

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.fn.readfile(filename))

        -- local num_lines = vim.api.nvim_buf_line_count(bufnr)

        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
        local start_line_base0 = entry.match.start_line_base0
        local end_line_base0 = entry.match.end_line_base0

        -- TODO use start_column and end_column (base 0)
        local last_col = -1
        -- TODO confirm hl.range is base0 for both line/col values on start and end
        vim.hl.range(bufnr, ns, "RagLineRange", { start_line_base0, 0 }, { end_line_base0, last_col }, {})
        logs:info("text: " .. entry.match.text)

        local ft = vim.filetype.match({ filename = filename }) or "text"

        vim.bo[bufnr].filetype = ft -- triggers FileType autocommands
        vim.bo[bufnr].syntax = "" -- avoid regex syntax if you only want TS
        -- require('telescope.previewers.utils').highlighter(bufnr, ft)

        -- tracking # is just to help race condition around moving cursor (in my own code, not in telescope's code which can also blow up on a race)
        latest_query_num = latest_query_num + 1
        local gen = latest_query_num
        -- logs:info("updating cursor in previewer: " .. gen) -- for debugging race condition
        vim.schedule(function()
            if gen ~= latest_query_num then
                -- logs:info("ignoring old gen in previewer: " .. gen) -- for debugging race condition
                return
            end
            if not vim.api.nvim_win_is_valid(winid) then
                return
            end
            if not vim.api.nvim_buf_is_loaded(bufnr) then
                return
            end
            vim.api.nvim_set_option_value("number", true, { win = winid })
            vim.api.nvim_set_option_value("relativenumber", false, { win = winid })

            vim.api.nvim_win_call(winid, function()
                local window_height = vim.api.nvim_win_get_height(winid)
                local num_highlight_lines = end_line_base0 - start_line_base0
                if num_highlight_lines <= window_height then
                    -- center it since it all fits
                    local center_line_0based = start_line_base0 + math.floor((num_highlight_lines) / 2)
                    pcall(vim.api.nvim_win_set_cursor, winid, { center_line_0based, 0 })
                    vim.cmd('normal! zz')
                else
                    -- doesn't all fit, so start on top line
                    vim.fn.winrestview({ topline = start_line_base0 })
                end
            end)
        end)
    end,
})

local sort_by_score = sorters.Sorter:new {
    -- core Sorter logic: ~/.local/share/nvim/lazy/telescope.nvim/lua/telescope/sorters.lua:122-160

    ---@param entry SemanticGrepTelescopeEntryMatch
    scoring_function = function(_self, prompt, ordinal, entry, cb_add, cb_filter)
        -- 0 <= score <= 1
        -- print("prompt: " .. vim.inspect(prompt))
        -- print("ordinal: " .. vim.inspect(ordinal))
        -- print("entry: " .. vim.inspect(entry))
        -- print("cb_add: " .. vim.inspect(cb_add))
        -- print("cb_filter: " .. vim.inspect(cb_filter))

        -- reverse order with 1-... IIUC this is in part b/c I have to use ascending sorting_strategy to workaround that bug with default (descending)
        return entry.match.rerank_rank
    end,

    highlighter = function(_, prompt, display)
        fzy = require "telescope.algos.fzy"
        return fzy.positions(prompt, display)
    end,
}
local Path = require "plenary.path"
cwd = vim.loop.cwd()
local path_abs = function(path)
    return Path:new(path):make_relative(cwd)
end

local get_icon_for_chunk_type = function(chunk_type)
    if chunk_type == "ts" then
        return "󱘎"
    elseif chunk_type == "lines" then
        return ""
    end
    -- TODO sub type the treesitter matches into functions, classes, etc ... and show icon to help? or is that overkill given SIG will clearly show what is what, most likely
end

local function semantic_grep_current_filetype_picker(opts)
    -- GOOD examples (multiple pickers in one nvim plugin):
    --  https://gitlab.com/davvid/telescope-git-grep.nvim/-/blob/main/lua/git_grep/init.lua?ref_type=heads

    -- TODO! show columns, with score too... basename on file? or some util to truncate?
    -- TODO! cancel previous queries? async too so not locking up UI?

    -- * this runs before picker opens, so you can gather context, i.e. current filetype, its LSP, etc
    ---@type LSPRagQueryRequest
    local lsp_rag_request = {
        query = "",
        instruct = "",
        vim_filetype = vim.o.filetype,
        current_file_absolute_path = files.get_current_file_absolute_path(),
    }
    local lsp_buffer_number = vim.api.nvim_get_current_buf()

    local displayer = entry_display.create {
        -- `:h telescope.pickers.entry_display`
        separator = " ",
        items = {
            { width = 5 },
            { width = 1 },
            { width = 60 },
            { width = 1 },
            { width = 40 },
        },
    }

    ---@param entry SemanticGrepTelescopeEntryMatch
    local function make_display(entry)
        -- FYI hl groups
        -- ~/.local/share/nvim/lazy/telescope.nvim/plugin/telescope.lua:11-92 i.e. TelescopeResultsIdentifier

        local score_percent = string.format("%.1f%%", entry.match.embed_score * 100)
        -- use percent_str where needed, e.g. in the display text
        local icon, icon_hlgroup = utils.get_devicons(entry.filename, false)
        local coordinates = ":"
        local match = entry.match
        if match.start_line_base0 then
            -- show base1 for humans
            local start_line_base1 = match.start_line_base0 + 1
            if match.start_column_base0 then
                local start_column_base1 = match.start_column_base0 + 1
                coordinates = string.format(":%s:%s:", start_line_base1, start_column_base1)
            else
                coordinates = string.format(":%s:", start_line_base1)
            end
        end
        local path_display = path_abs(entry.filename)
        -- TODO use ratio of window width to figure out limits?
        if #path_display > 60 then
            -- path_display = utils.path_smart(entry.filename)
            path_display = "..." .. path_display:sub(-55)
        end

        local line = path_display .. coordinates -- .. " " .. entry.match.text

        local contents = ""
        if match.signature and match.signature ~= "" then
            contents = entry.match.signature
        else
            contents = entry.match.text:sub(1, 30)
        end
        -- replace newlines with backslash n => \n shows
        contents = string.gsub(contents, "\n", "\\n") --  else telescope replaces new line with a | which then screws up icon color

        local chunk_type = get_icon_for_chunk_type(entry.match.type)

        return displayer {
            { score_percent, "TelescopeResultsNumber" },
            { icon,          icon_hlgroup },
            { line },
            { chunk_type },
            { contents,      "TelescopeResultsLine" },
        }
    end

    opts_previewer = {}
    picker = pickers:new({
        prompt_title = 'semantic grep - for testing RAG queries',
        sorting_strategy = 'ascending', -- default descending doesn't work right now due to bug with setting cursor position in results window

        finder = AsyncDynamicFinder:new({
            ---@param prompt string
            ---@param process_result fun(entry: SemanticGrepTelescopeEntryMatch)
            ---@param process_complete fun()
            ---@param entry_maker fun(match: LSPRankedMatch): SemanticGrepTelescopeEntryMatch
            fn = function(prompt, process_result, process_complete, entry_maker)
                if not prompt or prompt == '' then
                    -- this is necessary to clear the list, i.e. when you clear the prompt
                    process_complete()
                    return
                end
                -- function is called each time the user changes the prompt (text in the Telescope Picker)
                lsp_rag_request.query = prompt
                return _semantic_grep(lsp_rag_request, lsp_buffer_number, process_result, process_complete, entry_maker)
            end,

            ---@param match LSPRankedMatch
            ---@return SemanticGrepTelescopeEntryMatch
            entry_maker = function(match)
                ---@class SemanticGrepTelescopeEntryMatch
                ---@field match LSPRankedMatch
                ---@field value LSPRankedMatch
                ---@field display function|string -- use to create display text for picker
                ---@field filename string
                ---@field ordinal string -- for filtering? how so?
                local entry = {
                    -- required:
                    display = make_display, -- required, string|function
                    ordinal = match.text, -- required, for filtering? how so?
                    value = match, -- required, IIRC for getting selection (returns match).. though shouldn't it return the whole entry?!

                    match = match, -- PREFER THIS now that I have type hints
                    filename = match.file, -- default action uses these to jump to file location
                    -- valid = false -- true = hide this entry (or return nil for entire entry)
                }
                return entry
                -- optional second return value
            end,
        }),

        previewer = custom_buffer_previewer,
        sorter = sort_by_score,
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
            keymap({ 'n' }, '<leader>d', function()
                ---@type SemanticGrepTelescopeEntryMatch
                local selection = state.get_selected_entry()

                -- SHOW chunk details... i.e. compare to highlights in previewer
                logs:jsonify_info("selection:", selection.match)
                logs:info("selection.text:", selection.match.text)

                -- still blocks logs from updating, FYI...NBD
                vim.print(selection)
            end)
            return true
        end,
    })
    picker:find()
end

return require('telescope').register_extension {
    exports = {
        ask_semantic_grep = semantic_grep_current_filetype_picker,
    },
}
