local super_iter = require("devtools.super_iter")
local messages = require("devtools.messages")
local files = require("ask-openai.helpers.files")

local M = {}

---@return string file_path
function M.find_tags_file_for_this_workspace()
    return "tags"
    -- local result = vim.fn.findfile("tags", vim.fn.getcwd() .. ";")
end

---@alias ParsedTagLine { tag_name: string, file_name: string, ex_command : string }

---@param lines string[]
---@param file_ext string
---@return ParsedTagLine[]
function M.parse_tag_lines(lines, file_ext)
    return vim.iter(lines)
        :filter(function(line)
            -- filter on raw line
            -- IIAC I was filtering out comments (!)... not sure # is a comment though?
            return not line:match("^[#!]")
                -- PRN was I filtering out tests here? i.e. lua tests? OR?
                and not line:match("%.tests%.")
        end)
        :map(function(line)
            -- slit each line into fields
            local splits = vim.split(line, "\t", { plain = true, n = 2 })
            return {
                tag_name = splits[1],
                file_name = splits[2],
                ex_command = splits[3]:gsub(';"$', "")
            }
        end)
        :filter(function(tag)
            -- filter on line's fields
            -- FYI I was probably designing filters for lua at the time I built this:
            -- IIGC remove locals b/c those would already be covered by including current file as context
            --   OR they aren't relevant b/c only public exports from a module would be relevant in other modules (at least w.r.t. imports and usage)
            return not tag.ex_command:match("/^%s*local")
                -- match on file extension
                and tag.file_name:match("." .. file_ext .. "$")
        end)
        :totable()
end

---@param parsed_tag_lines ParsedTagLine[]
---@param file_name_func? (fun(file_name: string):string)
---@return string
function M.reassemble_tags(parsed_tag_lines, file_name_func)
    file_name_func = file_name_func or function(file_name)
        return file_name
    end

    return super_iter(parsed_tag_lines)
        :group_by(function(tag)
            return tag.file_name
        end)
        :map(function(key, items)
            local lines = { file_name_func(key) }
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

---@param file_path string
---@param language string
---@return ParsedTagLine[]
function M.get_parsed_tag_lines(file_path, language)
    return M.parse_tag_lines(files.read_file_lines(file_path), language)
end

---@param file_path string
---@param language string
---@return string tags_reassembled
function M.get_reassembled_text(file_path, language)
    return M.reassemble_tags(M.get_parsed_tag_lines(file_path, language))
end

---@return string file_path
function M.find_devtools_tags_file()
    return os.getenv("HOME") .. "/repos/github/g0t4/devtools.nvim/tags"
end

-- * reassembled entrypoints:
---@return string
function M.reassembled_tags_for_lua_devtools()
    return M.get_reassembled_text(
        M.find_devtools_tags_file(),
        "lua"
    )
end

---@return string
function M.reassembled_tags_for_this_workspace(language)
    local tags = M.find_tags_file_for_this_workspace()
    return M.get_reassembled_text(tags, language)
end

-- TODO fix ctags context to use this new all_reassembled_tags method
---@return string[]
function M.all_reassembled_tags()
    local language = M.get_language_for_current_buffer()
    local reassembeds = {
        -- todo more than one lib prompts!
        M.reassembled_tags_for_this_workspace(language),
    }
    if language == "lua" then
        table.insert(reassembeds, M.reassembled_tags_for_lua_devtools())
    end
    return reassembeds
end

-- * parsed_tag_lines (only) entrypoints:
---@return ParsedTagLine[]
function M.parsed_tag_lines_for_lua_devtools()
    return M.parse_tag_lines(files.read_file_lines(M.find_devtools_tags_file()), "lua")
end

---@return ParsedTagLine[]
function M.parsed_tag_lines_for_this_workspace(language)
    return M.parse_tag_lines(files.read_file_lines(M.find_tags_file_for_this_workspace()), language)
end

function M.get_language_for_current_buffer()
    -- PRN can add logic to map here
    return vim.bo.filetype
end

function M.dump_this()
    -- get current file's type
    local language = M.get_language_for_current_buffer()

    messages.header("Parsed lines for `" .. language .. "`")
    messages.ensure_open()
    messages.append(M.reassembled_tags_for_this_workspace(language))
    messages.scroll_back_before_last_append()
end

function M.setup()
    vim.api.nvim_create_user_command("AskDumpCTags", M.dump_this, {})
end

return M
