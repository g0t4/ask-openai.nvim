require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require("luassert")
local argv_formatter = require("ask-openai.agents.viewer.formatters.argv_formatter")

local function make_argv(...)
    local args = { ... }
    return args
end

describe("Test quote_argv_element via commandline_equivalent_for_argv", function()
    it("no spaces - remains unquoted", function()
        local result = argv_formatter.commandline_equivalent_for_argv(make_argv("ls", "-la", "/tmp"))
        assert.are.same("ls -la /tmp", result)
    end)

    it("with spaces in path - double quoted", function()
        local result = argv_formatter.commandline_equivalent_for_argv(make_argv("cat", "my file.txt"))
        assert.are.same('cat "my file.txt"', result)
    end)

    it("tab and newline count as whitespace and get quoted", function()
        local result_tab = argv_formatter.commandline_equivalent_for_argv(make_argv("echo", "I\thave\ttabs"))
        assert.are.same('echo "I\thave\ttabs"', result_tab)

        local result_nl = argv_formatter.commandline_equivalent_for_argv(make_argv("echo", "line1\nline2"))
        assert.are.same('echo "line1\nline2"', result_nl)
    end)

    it("has single quotes without double quotes - quotes with double", function()
        -- Qwen accidentally included the rest of the commandline as the second argv entry
        -- and thus it failed because that's not a cat-able file!
        local result = argv_formatter.commandline_equivalent_for_argv(make_argv("cat", "1780201044-trace.json | jq 'keys'"))
        assert.are.same("cat \"1780201044-trace.json | jq 'keys'\"", result)
    end)

    it("has double quotes but not single quotes - quotes with single", function()
        local result = argv_formatter.commandline_equivalent_for_argv(make_argv("git", "commit", "-m", 'with "double" quotes'))
        assert.are.same("git commit -m 'with \"double\" quotes'", result)
    end)

    it("has both quote types - escapes double and wraps in double", function()
        local result = argv_formatter.commandline_equivalent_for_argv(make_argv("echo", "she said \"hello\" and 'hi'"))
        assert.are.same('echo "she said \\"hello\\" and \'hi\'"', result)
    end)

    it("has empty argument - results in extra space", function()
        local result = argv_formatter.commandline_equivalent_for_argv(make_argv("echo", "", "foo"))
        assert.are.same("echo  foo", result)
    end)
end)

describe("Test format_run_process_command", function()
    it("argv transformed with quoting", function()
        local args = vim.json.encode({ argv = { "git", "commit", "-m", "here is my message" } })
        local result = argv_formatter.format_run_process_command(args)
        assert.are.same('git commit -m "here is my message"', result)
    end)

    it("command_line returns verbatim", function()
        local args = vim.json.encode({ command_line = "ls -la | grep foo" })
        local result = argv_formatter.format_run_process_command(args)
        assert.are.same("ls -la | grep foo", result)
    end)

    it("legacy command returns verbatim", function()
        local args = vim.json.encode({ command = "ls" })
        local result = argv_formatter.format_run_process_command(args)
        assert.are.same("ls", result)
    end)

    it("both argv and command_line raises error", function()
        local args = vim.json.encode({ command_line = "ls", argv = { "ls" } })
        local ok, err = pcall(argv_formatter.format_run_process_command, args)
        assert.is_false(ok)
        assert.string(err)
        assert(strfind(err, "Ambiguous run_process") ~= nil)
    end)

    it("entirely missing raises error", function()
        local args = vim.json.encode({ unknown = "value" })
        local ok, err = pcall(argv_formatter.format_run_process_command, args)
        assert.is_false(ok)
        assert.string(err)
        assert(strfind(err, "No command found") ~= nil)
    end)

    it("invalid json raises error", function()
        local ok, err = pcall(argv_formatter.format_run_process_command, "not valid json")
        assert.is_false(ok)
        assert.string(err)
        assert(strfind(err, "JSON decode failed") ~= nil)
    end)
end)
