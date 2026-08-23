require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require "luassert"
local should = require("devtools.tests.should")
local describe = require('devtools.tests.define.describe')
local only = require("devtools.tests.define.only")

local apply_patch = require("ask-openai.tools.inproc.apply_patch")

---@param filename string relative path within the apply_patch working directory
---@param content string content line(s), each prefixed with "+" already
---@return string
local function make_add_file_patch(filename, content)
    return "*** Begin Patch\n*** Add File: " .. filename .. "\n" .. content .. "\n*** End Patch\n"
end

--- run apply_patch inside an isolated temp dir so tests never touch the repo,
--- then always restore cwd and clean up the temp dir
---@param run fun(temp_dir: string)
local function in_temp_dir(run)
    local original_cwd = vim.fn.getcwd()
    local temp_dir = vim.fn.tempname() .. ".dir"
    print("temp_dir", temp_dir)
    vim.fn.mkdir(temp_dir, "p")
    vim.fn.chdir(temp_dir)

    local ok, err = pcall(run, temp_dir)

    -- always restore cwd and clean up, even on failure
    vim.fn.chdir(original_cwd)
    vim.fn.delete(temp_dir, "rf")

    assert.is_true(ok, err)
end

describe("apply_patch integration tests", function()
    it("add a file", function()
        in_temp_dir(function(temp_dir)
            local target_file = "hello.txt"
            local patch = make_add_file_patch(target_file, "+Hello world")

            local result
            local cancel = apply_patch.call({ patch = patch }, function(output)
                result = output
            end)
            assert.is_function(cancel, "call should return a cancel function")

            local got_callback = vim.wait(5000, function()
                return result ~= nil
            end, 20)
            assert.is_true(got_callback, "apply_patch callback never fired")

            -- success output is not flagged as an error (isError key is absent)
            assert.is_not_nil(result.result, "add file should produce a result")
            assert.is_nil(result.result.isError, "add file should not be flagged isError")

            -- file should actually be created in the temp dir
            local created_path = temp_dir .. "/" .. target_file
            assert.is_true(vim.fn.filereadable(created_path) == 1, "target file should exist")
            local created_contents = table.concat(vim.fn.readfile(created_path), "\n")
            assert.is_equal("Hello world", created_contents)
            print("DONE")
        end)
    end)

    it("immediate cancel does not create file", function()
        in_temp_dir(function(temp_dir)
            local target_file = "should_not_exist.txt"
            local patch = make_add_file_patch(target_file, "+Nope")

            local result
            local cancel = apply_patch.call({ patch = patch }, function(output)
                result = output
            end)
            assert.is_function(cancel, "call should return a cancel function")

            -- cancel immediately, before the external process has a chance to finish
            cancel()

            local got_callback = vim.wait(5000, function()
                return result ~= nil
            end, 20)
            assert.is_true(got_callback, "apply_patch callback never fired after cancel")

            -- canceled responses are flagged isError and labeled "canceled"
            assert.is_true(result.isError, "canceled response should be flagged isError")
            local content = result.result and result.result.content or {}
            assert.is_equal("canceled", content[1] and content[1].name,
                "canceled content should be labeled canceled")

            -- the file must not exist
            local created_path = temp_dir .. "/" .. target_file
            assert.is_true(vim.fn.filereadable(created_path) == 0, "target file should NOT exist, looks like CANCEL FAILED or was too slow?")
            print("DONE")
            -- FYI comment out the kill() call to test this fails
        end)
    end)

    it("invalid patch returns error with EXIT_CODE", function()
        in_temp_dir(function(temp_dir)
            -- "Frobnicate" is not a valid hunk header, so apply_patch should fail
            local bad_patch = "*** Begin Patch\n*** Frobnicate File: nope.txt\n*** End Patch\n"

            local result
            apply_patch.call({ patch = bad_patch }, function(output)
                result = output
            end)

            local got_callback = vim.wait(5000, function()
                return result ~= nil
            end, 20)
            assert.is_true(got_callback, "apply_patch callback never fired for invalid patch")

            assert.is_not_nil(result.result, "invalid patch should produce a result")
            -- error output flags isError nested under result
            assert.is_true(result.result.isError, "invalid patch should be flagged isError")
            local content = result.result.content or {}
            assert.is_not_nil(content[1], "invalid patch should include error text")
            -- non-zero exit is surfaced as a labeled EXIT_CODE content block
            assert.is_equal("EXIT_CODE", content[2] and content[2].name,
                "invalid patch should include EXIT_CODE")
            print("DONE")
        end)
    end)
end)
