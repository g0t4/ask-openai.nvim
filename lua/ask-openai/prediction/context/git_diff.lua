local messages = require("devtools.messages")
local ContextItem = require("ask-openai.prediction.context.item")

-- get a combined (per file) diff across X recent commits
--  exclude some files like uv.lock
-- git --no-pager diff -p HEAD~10..HEAD -- . ':(exclude)uv.lock'
--
-- THEN, I think I should split on filename and break each into its own file_sep
--
local M = {}

local function split_on_diff_headers(diff_output)
    local hunks = {}
    local start = 1

    while true do
        local find_start, find_end = diff_output:find("diff %-%-git a/.- b/.-\n", start)
        if not find_start then break end

        local next_start = diff_output:find("diff %-%-git a/.- b/.-\n", find_end + 1)
        if next_start then
            table.insert(hunks, diff_output:sub(find_start, next_start - 1))
            start = next_start
        else
            table.insert(hunks, diff_output:sub(find_start))
            break
        end
    end

    return hunks
end

local function git_diff()
    local cmd = "git --no-pager diff -p HEAD~10..HEAD -- . ':(exclude)uv.lock'"
    local handle = io.popen(cmd)
    local diff_output = handle:read("*a")

    handle:close()
    messages.append(cmd)

    return split_on_diff_headers(diff_output)
end

function get_context_items()
    local files = git_diff()
    local items = {}
    for _, file in ipairs(files) do
        local diff_lines = vim.split(file, "\n")
        -- get the filename from the diff header
        local file_name = vim.split(diff_lines[1], " ")[3]
        local diff_text = table.concat(diff_lines, "\n")
        -- TODO parse the diff into hunks and then each hunk into a ContextItem
        -- NOTE: the diff is already split into hunks, so we can just use the diff_text
        --       for each hunk
        local context_item = ContextItem:new(diff_text, file_name)
        table.insert(items, context_item)
    end
    return items
end

function test()
    messages.ensure_open()
    for _, hunk in pairs(git_diff()) do
        messages.divider()
        messages.append(hunk)
    end
    -- TODO! inject the diffs as context => 1 file per diff? => name file with the "diff --git ..." line? (don't parse it!)
end

function M.setup()
    -- TODO when done, remove this
    vim.keymap.set("n", "<space>g", test, { silent = true })
end

return M
