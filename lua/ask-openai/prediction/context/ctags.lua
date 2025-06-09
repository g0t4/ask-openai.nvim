local M = {}


function M.find_tag_file()
    local result = vim.fn.findfile("tags", vim.fn.getcwd() .. ";")
    if result ~= "" then
        return result
    end
end

function M.get_tag_list()
    local result = {}
    for line in io.lines(M.find_tag_file()) do
        table.insert(result, line)
    end
    return result
end

function M.get_prompt()
    local tags = M.get_tag_list()
    if #tags == 0 then
        return ""
    end
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
