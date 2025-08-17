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

function _context_query_sync(message, lsp_buffer_number)
    messages.header("context query")
    messages.append("message" .. vim.inspect(message))
    messages.append("lsp_buffer_number" .. lsp_buffer_number)
    lsp_buffer_number = lsp_buffer_number or 0


    message.text = "setmantic_grep" -- TODO remove later
    -- TODO refine instructions
    message.instruct = "Semantic grep of relevant code for display in neovim, using semantic_grep extension to telescope"
    -- current_file_absolute_path  -- PRN default?
    -- vim_filetype  -- PRN default?

    -- TODO see my _context_query for ASYNC example once I am done w/ sync testing
    -- I should be able to stream in results
    -- TODO handle canceling previous query on next one!
    -- in telescope can I have the user type in a prompt and decide when to execute it?
    --  or is it live search only?

    local results = vim.lsp.buf_request_sync(lsp_buffer_number, "workspace/executeCommand", {
        command = "context.query",
        arguments = { message },
    })
    -- messages.append("results: " .. vim.inspect(results))
    if not results then
        messages.append("failed to get results")
        return {}
    end

    return results[1].result.matches or {}
end

local terminfo_previewer_bat = previewers.new_termopen_previewer({
    get_command = function(entry)
        match = entry.match
        messages.append("entry: " .. vim.inspect(match))

        local f = match.file
        return {
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
    end,
})

local function semantic_grep_current_filetype_picker(opts)
    -- GOOD examples (multiple pickers in one nvim plugin):
    --  https://gitlab.com/davvid/telescope-git-grep.nvim/-/blob/main/lua/git_grep/init.lua?ref_type=heads

    -- * this runs before picker opens, so you can gather context, i.e. current filetype, its LSP, etc
    messages.append("opts" .. vim.inspect(opts))
    local query_args = {
        -- TODO should I have one picker that is specific to current file type only
        --  and then another that searches code across all filetypes?
        --  use re-ranker in latter case!
        filetype = vim.o.filetype,
        current_file_absolute_path = files.get_current_file_absolute_path(),
    }
    messages.append("query_args:", vim.inspect(query_args))
    local lsp_buffer_number = vim.api.nvim_get_current_buf()

    opts_previewer = {}
    pickers.new({ opts }, {
        prompt_title = 'semantic grep - for testing RAG queries',
        finder = finders.new_dynamic({
            fn = function(prompt)
                -- function is called each time the user changes the prompt (text in the Telescope Picker)
                query_args.text = prompt
                -- TODO make async query instead using buf_request instead of buf_request_sync
                return _context_query_sync(query_args, lsp_buffer_number)
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
                -- messages.append("match: " .. vim.inspect(match))
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
        previewer = terminfo_previewer_bat,

        sorter = sorters.get_generic_fuzzy_sorter(),
        attach_mappings = function(prompt_bufnr, keymap)
            -- actions.select_default:replace(function()
            --     -- actions.close(prompt_bufnr)
            --     local selection = state.get_selected_entry()
            --     -- TODO jump to start line of match
            --     -- vim.api.nvim_command('vsplit ' .. link)
            --     -- messages.append("selected entry: " .. vim.inspect(selection))
            -- end)
            keymap({ 'i', 'n' }, 'c', function()
                -- add to context
                -- TODO add action for adding to an explicit context!
                -- TODO it would also be useful to have add to explicit context on a regular rg file search
            end)
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
