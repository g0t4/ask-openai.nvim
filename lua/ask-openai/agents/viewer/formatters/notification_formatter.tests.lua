require("ask-openai.helpers.test_setup").modify_package_path()
local assert = require("luassert")
local notification_formatter = require("ask-openai.agents.viewer.formatters.notification_formatter")

describe("Test format_notification_message", function()
    it("plain string returns as-is", function()
        local result = notification_formatter.format_notification_message("Running task...")
        assert.are.same("Running task...", result)
    end)

    it("empty string returns as-is", function()
        local result = notification_formatter.format_notification_message("")
        assert.are.same("", result)
    end)

    it("nil returns as-is", function()
        local result = notification_formatter.format_notification_message(nil)
        assert.are.same(nil, result)
    end)

    it("does not match partial 'Running tool' pattern", function()
        local result = notification_formatter.format_notification_message("Running tools in progress")
        assert.are.same("Running tools in progress", result)
    end)

    describe("ls tool", function()
        it("formats simple path", function()
            local msg = "Running tool: ls args={'path': '/Users/wesdemos/repos/github/g0t4/mcp-servers'}"
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same("ls /Users/wesdemos/repos/github/g0t4/mcp-servers", result)
        end)

        it("formats path with spaces", function()
            local msg = "Running tool: ls args={'path': '/path/to/my folder'}"
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same('ls "/path/to/my folder"', result)
        end)
    end)

    describe("read_file tool", function()
        it("formats with file_path", function()
            local msg = "Running tool: read_file args={'file_path': '/Users/wesdemos/repos/github/g0t4/mcp-servers/README.md'}"
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same("read_file /Users/wesdemos/repos/github/g0t4/mcp-servers/README.md", result)
        end)

        it("formats with spaces in path", function()
            local msg = "Running tool: read_file args={'file_path': '/path/to/my file.txt'}"
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same('read_file "/path/to/my file.txt"', result)
        end)
    end)

    describe("glob tool", function()
        it("formats with pattern only", function()
            local msg = "Running tool: glob args={'pattern': 'src/git/src/mcp_server_git/*.py'}"
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same("glob src/git/src/mcp_server_git/*.py", result)
        end)

        it("formats with pattern and path", function()
            local msg = "Running tool: glob args={'pattern': 'src/**/*.ts', 'path': '/Users/wesdemos/repos/github/g0t4/mcp-servers/src'}"
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same("glob src/**/*.ts in /Users/wesdemos/repos/github/g0t4/mcp-servers/src", result)
        end)

        it("formats pattern with spaces", function()
            local msg = "Running tool: glob args={'pattern': '*. ts', 'path': '/path'}"
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same([[glob "*. ts" in /path]], result)
        end)
    end)

    describe("execute tool", function()
        it("formats with command", function()
            local msg = "Running tool: execute args={'command': 'find /Users/wesdemos/repos/github/g0t4/mcp-servers/src/time -type f'}"
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same([[find /Users/wesdemos/repos/github/g0t4/mcp-servers/src/time -type f]], result)
        end)

        it("formats command with spaces (wrapped for clarity)", function()
            local msg = "Running tool: execute args={'command': 'ls -la /path/to/my files'}"
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same([[ls -la /path/to/my files]], result)
        end)

        it("formats command without spaces (no quotes needed)", function()
            local msg = "Running tool: execute args={'command': 'ls'}"
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same("ls", result)
        end)
    end)

    describe("write_file tool", function()
        it("formats with file_path", function()
            local msg = "Running tool: write_file args={'file_path': '/tmp/output.txt'}"
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same("write_file /tmp/output.txt", result)
        end)
    end)

    describe("edit_file tool", function()
        it("formats with file_path", function()
            local msg = "Running tool: edit_file args={'file_path': '/tmp/edit.txt'}"
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same("edit_file /tmp/edit.txt", result)
        end)
    end)

    describe("search tool", function()
        it("formats with query", function()
            local msg = "Running tool: search args={'query': 'find all functions'}"
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same([[search "find all functions"]], result)
        end)

        it("formats with q field", function()
            local msg = "Running tool: search args={'q': 'hello world'}"
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same([[search "hello world"]], result)
        end)
    end)

    describe("run_process delegation", function()
        it("delegates to argv_formatter for run_process with command_line", function()
            local msg = 'Running tool: run_process args={"command_line": "ls -la | grep foo"}'
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same("ls -la | grep foo", result)
        end)

        it("delegates to argv_formatter for run_process with argv", function()
            local msg = 'Running tool: run_process args={"argv": ["cat", "my file.txt"]}'
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same('cat "my file.txt"', result)
        end)
    end)

    describe("unknown tool fallback", function()
        it("returns original message for unknown tool", function()
            local msg = "Running tool: unknown_tool args={'foo': 'bar'}"
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same(msg, result)
        end)

        it("returns original message when args fail to parse", function()
            local msg = "Running tool: ls args=broken args"
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same(msg, result)
        end)
    end)

    describe("JSON-style args", function()
        it("parses JSON-style args for execute", function()
            local msg = 'Running tool: execute args={"command": "ls -la"}'
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same("ls -la", result)
        end)

        it("parses JSON-style args for read_file", function()
            local msg = 'Running tool: read_file args={"file_path": "/foo/bar.md"}'
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same("read_file /foo/bar.md", result)
        end)
    end)

    describe("register_tool_formatter extension", function()
        it("allows registering custom tool formatter", function()
            notification_formatter.register_tool_formatter("custom_tool", function(args)
                return "custom: " .. (args.command or "?")
            end)

            local msg = 'Running tool: custom_tool args={"command": "foo"}'
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same("custom: foo", result)
        end)

        it("custom formatter does not affect other tools", function()
            local msg = "Running tool: ls args={'path': '/bar'}"
            local result = notification_formatter.format_notification_message(msg)
            assert.are.same("ls /bar", result)
        end)
    end)
end)
