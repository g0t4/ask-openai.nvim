local super_iter = require("devtools.super_iter")
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
                and tag.file_name:match("." .. language .. "$")
        end)
        :totable()
end

function M.reassembled_tags(parsed_lines)
    return super_iter(parsed_lines)
        :group_by(function(tag)
            return tag.file_name
        end)
        :map(function(key, items)
            local lines = { key }
            for _, tag in ipairs(items) do
                -- FYI stripping /^ $/ removed 19% of tokens in a test run
                -- also strip leading spaces... not sure it would be useful anyways (did not analyze savings from that)
                local stripped_ex_command = tag.ex_command
                    :gsub("/^%s*", "")
                    :gsub("$/", "")
                table.insert(lines, "    " .. stripped_ex_command)
            end
            return table.concat(lines, "\n")
        end)
        :join("\n")
end

function M.read_and_reassemble(file)
    return M.reassembled_tags(
        M.parse_tag_lines(
            M.get_tag_lines(file),
            "lua"
        )
    )
end

function M.get_devtools_tag_lines()
    local devtools_tags = os.getenv("HOME") .. "/repos/github/g0t4/devtools.nvim/tags"
    return M.read_and_reassemble(devtools_tags)
end

function M.get_ctag_files()
    return {
        -- todo more than one lib prompts!
        M.get_devtools_tag_lines(),
        M.get_this_project_tag_lines(),
    }
end

function M.get_this_project_tag_lines()
    local tags = M.find_tag_file()
    return M.read_and_reassemble(tags)
end

return M
