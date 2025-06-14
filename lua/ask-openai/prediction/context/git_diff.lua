local messages = require("devtools.messages")
-- get a combined (per file) diff across X recent commits
--  exclude some files like uv.lock
-- git --no-pager diff -p HEAD~10..HEAD -- . ':(exclude)uv.lock'
--
-- THEN, I think I should split on filename and break each into its own file_sep
--

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

function test()
    messages.ensure_open()
    for _, hunk in pairs(git_diff()) do
        messages.divider()
        messages.append(hunk)
    end
end

vim.keymap.set("n", "<space>g", test, { silent = true })
