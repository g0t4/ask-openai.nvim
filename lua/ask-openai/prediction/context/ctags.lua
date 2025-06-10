local M = {}

function M.find_tag_file()
    return "tags"
    -- local result = vim.fn.findfile("tags", vim.fn.getcwd() .. ";")
end

function M.get_tag_lines(file_path)
    local lines = {}
    for line in io.lines(file_path) do
        table.insert(lines, line)
    end
    return lines
end

function M.parse_tag_lines(lines, language)
    language = language or "lua"

    return vim.iter(lines)
        -- filter on raw lines
        :filter(function(line)
            return not line:match("^[#!]")
                and not line:match("%.tests%.")
        end)
        -- split her up!
        :map(function(line)
            local splits = vim.split(line, "\t", { plain = true, n = 2 })
            return {
                tag_name = splits[1],
                file_name = splits[2],
                ex_command = splits[3]:gsub(';"$', "")
            }
        end)
        -- filter on fields
        :filter(function(tag)
            return not tag.ex_command:match("/^%s*local")
        end)
        :totable()
end

function M.get_devtools_tag_lines()
    local devtools_tags = os.getenv("HOME") .. "/repos/github/g0t4/devtools.nvim/tags"
    local tags = M.get_tag_lines(devtools_tags)

    return table.concat(tags, "\n") .. "\n"
end

function M.get_ctag_files()
    return {
        -- todo more than one lib prompts!
        M.get_devtools_tag_lines(),
        M.get_this_project_tag_lines(),
    }
end

function M.get_this_project_tag_lines()
    local tags = M.get_tag_lines(M.find_tag_file())
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
