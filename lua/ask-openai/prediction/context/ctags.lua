local M = {}


function M.find_tag_file()
    local result = vim.fn.findfile("tags", vim.fn.getcwd() .. ";")
    if result ~= "" then
        return result
    end
end

function M.get_tag_list(file_path)
    local result = {}
    for line in io.lines(file_path) do
        table.insert(result, line)
    end
    return result
end

function M.get_devtools_tags()
    local devtools_tags = "~/repos/github/g0t4/devtools.nvim/tags"
    local tags = M.get_tag_list(devtools_tags)
    return table.concat(tags, "\n") .. "\n"
end

function M.get_ctag_files()
    return {
        -- todo more than one lib prompts!
        M.get_devtools_tags(),
        M.get_my_tags(),
    }
end

function M.get_my_tags()
    local tags = M.get_tag_list(M.find_tag_file())
    return table.concat(tags, "\n") .. "\n"
    -- TODO! filter what I want to save on tokens?
    --   drop last column, AFAICT its useless for lua
    --   drop NOT lua lines
    --
    -- for _, line in ipairs(tags) do
    --     local tag_name = line:match("^(.*)\t")
    --     prompt_text = prompt_text .. "- `" .. tag_name .. "`\n"
    -- end
end

return M
