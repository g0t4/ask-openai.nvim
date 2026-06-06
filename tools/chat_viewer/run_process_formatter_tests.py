import json
import pytest

from tools.chat_viewer.run_process_formatter import (
    format_heredoc_stdin,
    commandline_equivalent_for_argv,
    format_run_process_command,
)

class TestFormatArgv:

    def test_no_spaces_remains_unquoted(self):
        formatted = commandline_equivalent_for_argv(["ls", "-la", "/tmp"])
        assert formatted == "ls -la /tmp"

    def test_with_spaces_in_path_is_double_quoted(self):
        formatted = commandline_equivalent_for_argv(["cat", "my file.txt"])
        assert formatted == 'cat "my file.txt"'

    def test_tab_and_newline_count_as_whitespace_and_get_quoted(self):
        assert commandline_equivalent_for_argv(["echo", "I\thave\ttabs"]) == 'echo "I\thave\ttabs"'
        assert commandline_equivalent_for_argv(["echo", "line1\nline2"]) == 'echo "line1\nline2"'

    def test_has_single_quotes_without_double_quotes__quotes_with_double(self):
        """If no double quotes in value, use double quotes."""
        # FYI real failures example from Qwen3.6, that made me realize I was missing quoting the argv when showing it as a commandline!
        assert commandline_equivalent_for_argv([
            "cat",
            # Qwen accidentally included the rest of the commandline as the second argv entry and thus it failed because that's not a cat-able file!
            "1780201044-trace.json | jq 'keys'",
        ]) == "cat \"1780201044-trace.json | jq 'keys'\""

    def test_has_double_quotes__quotes_with_single(self):
        """If value has double quotes but not single quotes, use single quotes."""
        formatted = commandline_equivalent_for_argv(['git', 'commit', '-m', 'with "double" quotes'])
        assert formatted == "git commit -m 'with \"double\" quotes'"

    def test_has_both_quote_types__quotes_with_double(self):
        """If both quote types exist, escape double and wrap in double."""
        formatted = commandline_equivalent_for_argv(['echo', 'she said "hello" and \'hi\''])
        assert formatted == 'echo "she said \\"hello\\" and \'hi\'"'

    def test_has_empty_argument__results_in_extra_space(self):
        # ? do I want to change this to skip it?
        assert commandline_equivalent_for_argv(["echo", "", "foo"]) == "echo  foo"

class TestFormatRunProcessCommand:

    def test_argv_transformed(self):
        args = json.dumps({"argv": ["git", "commit", "-m", "here is my message"]})
        assert format_run_process_command(args) == 'git commit -m "here is my message"'

    def test_command_line__returns_verbatim(self):
        args = json.dumps({"command_line": "ls -la | grep foo"})
        assert format_run_process_command(args) == "ls -la | grep foo"

    def test_legacy_command__returns_verbatim(self):
        args = json.dumps({"command": "ls"})
        assert format_run_process_command(args) == "ls"

    def test_both_argv_and_command_line__raises_ValueError(self):
        """Should raise ValueError when both are set."""
        args = json.dumps({"command_line": "ls", "argv": ["ls"]})
        with pytest.raises(ValueError, match="Ambiguous run_process"):
            format_run_process_command(args)

    def test_entirely_missing__raises_ValueError(self):
        """Should raise ValueError when no command found."""
        args = json.dumps({"unknown": "value"})
        with pytest.raises(ValueError, match="No command found"):
            format_run_process_command(args)

    def test_invalid_json__raises_JSONDecodeError(self):
        """Should raise JSONDecodeError for invalid JSON."""
        with pytest.raises(json.JSONDecodeError):
            format_run_process_command("not valid json")


class TestFormatHeredocStdin:

    def test_no_trailing_newline__adds_one_before_delimiter(self):
        """When stdin_text doesn't end with \\n, add one before the delimiter."""
        result = format_heredoc_stdin("hello world")
        assert result == "<<'STDIN_TEXT'\nhello world\nSTDIN_TEXT'"

    def test_with_trailing_newline__no_extra_newline(self):
        """When stdin_text already ends with \\n, don't add another."""
        result = format_heredoc_stdin("hello world\n")
        assert result == "<<'STDIN_TEXT'\nhello world\nSTDIN_TEXT'"
