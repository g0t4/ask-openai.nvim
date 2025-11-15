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

local last_msg_id, cancel_last_requests


---@param lsp_rag_request LSPRagQueryRequest
---@param lsp_buffer_number integer
---@param process_result fun(entry: SemanticGrepTelescopeEntryMatch)
---@param process_complete fun()
---@param entry_maker fun(match: LSPRankedMatch): SemanticGrepTelescopeEntryMatch
function _semantic_grep(lsp_rag_request, lsp_buffer_number, process_result, process_complete, entry_maker)
    if cancel_last_requests then
        logs:error("canceling previous request, last_msg_id: " .. vim.inspect(last_msg_id))
        cancel_last_requests()
        cancel_last_requests = nil
    end

    lsp_buffer_number = lsp_buffer_number or 0

    logs:warn("requesting semantic_grep, last_msg_id: " .. vim.inspect(last_msg_id))
    local msg_id, cancel_my_request
    msg_id, cancel_my_request = vim.lsp.buf_request(lsp_buffer_number, "workspace/executeCommand", {
            command = "semantic_grep",
            arguments = { lsp_rag_request },
        },
        ---@param result LSPRagQueryResult
        function(err, result, ctx)
            -- logs:warn("semantic_grep callback: " .. vim.inspect({ err = err, result = result, ctx = ctx }))
            if last_msg_id ~= msg_id then
                -- only the last request should update the picker!
                -- prior requests may complete but are still cancelled
                return
            end

            -- because last request is this same request's response... then clear the cancel handler
            --   nothing left to cancel
            --   and IIUC this is going to run to completion before anything else can start anyways
            cancel_last_requests = nil -- no reason to cancel

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
        end
    )
    cancel_last_requests = cancel_my_request
    last_msg_id = msg_id -- this is a number

    logs:warn("client_request_ids: " .. vim.inspect(last_msg_id))
end

-- * RAG match highlighting
local ns = vim.api.nvim_create_namespace("rag_preview")
-- -- I want my own highlight style (not Search)
local hlgroup = "RagHighlightMatch"
vim.api.nvim_set_hl(0, hlgroup, { bg = "#414858" })

-- * chunk type colors
local hlgroup_light_green = "RagChunkTypeTreesitter"
vim.api.nvim_set_hl(0, hlgroup_light_green, { fg = "#b0d5a6" })
local hlgroup_light_red = "RagChunkTypeUncoveredCode"
vim.api.nvim_set_hl(0, hlgroup_light_red, { fg = "#e24040" })

local preview_content_type = 0
local function is_file_preview()
    return preview_content_type == 0
end
local function is_entry_debug_preview()
    return preview_content_type == 1
end
local function is_chunk_text_preview()
    return preview_content_type == 2
end
local function reverse_cycle_preview_content()
    preview_content_type = (preview_content_type - 1) % 3
end
local function cycle_preview_content()
    preview_content_type = (preview_content_type + 1) % 3
end

local custom_buffer_previewer = previewers.new_buffer_previewer({

    title = "Semantic Grep", -- static title when no entry selected
    dyn_title = function(_, entry)
        if entry then
            local path = vim.fn.fnamemodify(entry.filename, ":~:.") -- . == relative to CWD => fallback to ~ for relative to home dir
            if entry.lnum then
                return path .. ":" .. entry.lnum
            end
            return path
        end
        return "Semantic Grep - No matches" -- unsure this ever happens, I think static is used when no results
    end,

    ---@param entry SemanticGrepTelescopeEntryMatch
    define_preview = function(self, entry)
        local filename = entry.filename
        local winid = self.state.winid
        local bufnr = self.state.bufnr

        -- TODO! toggle to switch preview contents! (maybe subdivide define_preview to isolate each view since it is not just contents, but also selection, filetype, etc)
        if is_file_preview() then
            -- might not match RAG chunk text
            -- so far, I haven't noticed this, but it might not be obvious beyond a bad match or not quite right match!
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.fn.readfile(filename))
        elseif is_entry_debug_preview() then
            -- TODO mark as lua language b/c vim.inspect spits out lua table syntax
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(vim.inspect(entry), "\n"))
        elseif is_chunk_text_preview() then
            -- useful to compare if there is a discrepency vs file on-disk
            -- also a bit easier way to visualize full chunk text, especially if I add non-contiguous nodes in one chunk
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(entry.match.text, "\n"))
        else
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "FAIL SAUCE" })
        end

        -- * non-contiguous nodes w/in a chunk
        -- - one RAG chunk has nodes that are not neighbors lexically, but are neighbors semantically
        --   i.e. python module's top-level statements => basically akin to a "module global function"
        -- - could do actual file too and have multiple regions selected, with arrow/keymap to jump up/down (perhaps Ctrl-j/k) between nodes
        --   can use mouse to move file window to scroll buffer and see diff parts, so completely reasonable to add multi selection

        ---@type string|nil
        local ft = "lua"
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
        local start_line_base0 = entry.match.start_line_base0
        local end_line_base0 = entry.match.end_line_base0

        if is_file_preview() then
            -- PRN use start_column and end_column (base 0)
            local last_col = -1
            -- TODO confirm hl.range is base0 for both line/col values on start and end
            vim.hl.range(bufnr, ns, "RagHighlightMatch", { start_line_base0, 0 }, { end_line_base0, last_col }, {})

            ft = vim.filetype.match({ filename = filename })
        elseif is_entry_debug_preview() then
            ft = "lua"
        elseif is_chunk_text_preview() then
            -- FYI no selection b/c it's just the chunk text!
            ft = vim.filetype.match({ filename = filename })
        end

        if not ft then
            -- ! DO NOT WASTE MORE TIME ON vim.filetype.match, it's a cluster fuck
            -- JUST MAP W/E does not fit for now, it doesn't matter... you're not the first person to have this issue with vim.filetype.match so just ignore it
            -- DO NOT RELY ON vim.filetype... even though the docs suggest it has no qualifications it apparently doesn't handle any of the legacy vimscript ftplugin logic? filetype.vim? (IIUC)
            if filename:match("%.ts$") then
                ft = "typescript"
            else
                logs:info("filetype match failed, please manually add the mapping for the file extension (ft=" .. tostring(ft) .. ") for filename: " .. filename)
                ft = ""
            end
        end

        vim.bo[bufnr].filetype = ft
        vim.bo[bufnr].syntax = "" -- only TS
        -- require('telescope.previewers.utils').highlighter(bufnr, ft)

        -- tracking # is just to help race condition around moving cursor (in my own code, not in telescope's code which can also blow up on a race)
        latest_query_num = latest_query_num + 1
        local gen = latest_query_num
        vim.schedule(function()
            if gen ~= latest_query_num then
                return
            end
            if not vim.api.nvim_win_is_valid(winid) then
                return
            end
            if not vim.api.nvim_buf_is_loaded(bufnr) then
                return
            end

            -- * delayed window setup
            vim.api.nvim_set_option_value("number", true, { win = winid })
            vim.api.nvim_set_option_value("relativenumber", false, { win = winid })

            function scroll_to_first_highlight()
                if not is_file_preview() then
                    -- PRN during a change of preview type, would I need to scroll to top for non-file previews?
                    return
                end

                local window_height = vim.api.nvim_win_get_height(winid)
                local num_highlight_lines = end_line_base0 - start_line_base0
                if num_highlight_lines <= window_height then
                    -- * center it
                    local center_line_0based = start_line_base0 + math.floor((num_highlight_lines) / 2)
                    pcall(vim.api.nvim_win_set_cursor, winid, { center_line_0based, 0 })
                    vim.cmd('normal! zz')
                else
                    -- * doesn't all fit, so start on top line
                    vim.fn.winrestview({ topline = start_line_base0 })
                end
            end

            vim.api.nvim_win_call(winid, scroll_to_first_highlight)
        end)
    end,
})

local sort_by_score = sorters.Sorter:new {
    -- core Sorter logic: ~/.local/share/nvim/lazy/telescope.nvim/lua/telescope/sorters.lua:122-160

    ---@param entry SemanticGrepTelescopeEntryMatch
    scoring_function = function(_self, prompt, ordinal, entry, cb_add, cb_filter)
        -- 0 <= score <= 1
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

---@param chunk_type ChunkType
---@return string icon, string hlgroup
local get_icon_for_chunk_type = function(chunk_type)
    if chunk_type == "ts" then
        return "󱘎", "RagChunkTypeTreesitter"
    elseif chunk_type == "lines" then
        return "", "Normal"
    elseif chunk_type == "uncovered" then
        return "󱎘", "RagChunkTypeUncoveredCode"
    end
end

function semantic_grep_current_filetype_picker(opts)
    -- * this runs before picker opens, so you can gather context, i.e. current filetype, its LSP, etc
    ---@type LSPRagQueryRequest
    local lsp_rag_request = {
        -- instruct => let server set the Instruct for semantic_grep (would be "Semantic grep of relevant code ...")
        query = "",
        vimFiletype = vim.o.filetype,
        currentFileAbsolutePath = files.get_current_file_absolute_path(),
        topK = 50,
        skipSameFile = false,
        -- PRN other file types?
    }
    -- FYI right now languages is for GLOBAL/EVERYTHING only
    lsp_rag_request.languages = opts.languages

    local lsp_buffer_number = vim.api.nvim_get_current_buf()

    local displayer = entry_display.create {
        -- `:h telescope.pickers.entry_display`
        separator = " ",
        items = {
            { width = 5 },
            { width = 5 },
            { width = 5 },
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

        local embed_score_percent = string.format("%.1f%%", entry.match.embed_score * 100)
        local rerank_score_percent = string.format("%.1f%%", entry.match.rerank_score * 100)
        -- use percent_str where needed, e.g. in the display text
        local icon, icon_hlgroup = utils.get_devicons(entry.filename, false)
        local coordinates = ":"
        local match = entry.match
        if match.start_line_base0 then
            -- show base1 for humans
            local start_line_base1 = match.start_line_base0 + 1
            coordinates = string.format(":%s", start_line_base1)
            -- FYI using :# means I can control+click in iterm to open the result in a new window
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

        local chunk_type, chunk_type_hlgroup = get_icon_for_chunk_type(entry.match.type)

        return displayer {
            { rerank_score_percent, "TelescopeResultsNumber" },
            { match.rerank_rank,    "TelescopeResultsNumber" },
            { embed_score_percent,  "TelescopeResultsNumber" },
            { match.embed_rank,     "TelescopeResultsNumber" },
            { icon,                 icon_hlgroup },
            { line },
            { chunk_type,           chunk_type_hlgroup },
            { contents,             "TelescopeResultsLine" },
        }
    end

    opts_previewer = {}
    local prompt_title = 'semantic grep 󰕡 ' .. tostring(vim.o.filetype)
    if opts.languages == "GLOBAL" then
        -- TODO list global languages here? from rag.yaml?
        prompt_title = 'semantic grep 󰕡 GLOBAL languages'
    end
    if opts.languages == "EVERYTHING" then
        prompt_title = 'semantic grep 󰕡 EVERYTHING'
    end
    picker = pickers:new({
        prompt_title = prompt_title,
        prompt_prefix = '󰕡 ',
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

                    -- default action uses these to open to file + location
                    filename = match.file, -- default action uses these to jump to file location
                    lnum = match.start_line_base0 + 1,
                    col = match.start_column_base0 + 1,

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
            --     -- * add to Ask context! for future prompts
            -- end)
            -- FYI <tab> in insert mode normally allows multi-select, so if you need that then add it back, for now I want it to switch views too
            keymap({ 'i', 'n' }, '<S-Tab>', function()
                reverse_cycle_preview_content()

                local picker = state.get_current_picker(prompt_bufnr)
                picker:refresh_previewer()
            end)
            keymap({ 'i', 'n' }, '<Tab>', function()
                -- PRN add keymap to jump to specific view?
                cycle_preview_content()

                local picker = state.get_current_picker(prompt_bufnr)
                picker:refresh_previewer()
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
