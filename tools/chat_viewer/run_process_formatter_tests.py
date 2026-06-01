"""Tests for run_process_formatter module."""

import json

import pytest

from tools.chat_viewer.run_process_formatter import (
    _format_argv_element,
    format_argv,
    format_run_process_command,
)


class TestFormatArgvElement:
    """Tests for _format_argv_element helper."""

    def test_no_space_stays_bare(self):
        """Elements without whitespace should remain unquoted."""
        assert _format_argv_element("cat") == "cat"

    def test_single_space_gets_double_quoted(self):
        """Elements with spaces get wrapped in double quotes."""
        assert _format_argv_element("file with spaces.txt") == '"file with spaces.txt"'
        assert _format_argv_element("my git commit description") == '"my git commit description"'

    def test_tab_and_newline_count_as_whitespace(self):
        """Tab and newline characters trigger quoting."""
        assert _format_argv_element("file\twith\ttab") == '"file\twith\ttab"'
        assert _format_argv_element("line1\nline2") == '"line1\nline2"'

    def test_no_double_quote_uses_double_quotes(self):
        """If no double quotes in value, use double quotes."""
        assert _format_argv_element("path with 'single' quotes") == '"path with \'single\' quotes"'

    def test_has_double_quote_falls_back_to_single(self):
        """If double quotes exist but not single, use single quotes."""
        result = _format_argv_element('with "double" quotes')
        assert result == "'with \"double\" quotes'"

    def test_both_quotes_escapes_double(self):
        """If both quote types exist, escape double and wrap in double."""
        result = _format_argv_element('she said "hello" and \'hi\'')
        assert result == '"she said \\"hello\\" and \'hi\'"'

    def test_complex_pipe_command(self):
        """Real-world trace example with pipe and jq (has single quotes, no double)."""
        result = _format_argv_element(
            "~/repos/github/g0t4/datasets/ask_traces/agents/2026-05/2026-05-30_008/1780201044-trace.json | jq 'keys'"
        )
        # Has spaces, has single quotes around keys, no double quotes
        # So it should wrap in double quotes
        assert result == '"~/repos/github/g0t4/datasets/ask_traces/agents/2026-05/2026-05-30_008/1780201044-trace.json | jq \'keys\'"'

    def test_empty_string(self):
        """Empty string should remain empty."""
        assert _format_argv_element("") == ""


class TestFormatArgv:
    """Tests for format_argv function."""

    def test_simple_command(self):
        """Basic command without spaces."""
        result = format_argv(["ls", "-la", "/tmp"])
        assert result == "ls -la /tmp"

    def test_with_spaces_in_path(self):
        """Command with spaces in arguments."""
        result = format_argv(["cat", "my file.txt"])
        assert result == 'cat "my file.txt"'

    def test_trace_example(self):
        """Real trace example with pipe and jq."""
        argv = [
            "cat",
            "~/repos/github/g0t4/datasets/ask_traces/agents/2026-05/2026-05-30_008/1780201044-trace.json | jq 'keys'",
        ]
        result = format_argv(argv)
        assert "jq 'keys'" in result
        assert result.startswith("cat ")

    def test_all_no_spaces(self):
        """No element has whitespace, so nothing is quoted."""
        result = format_argv(["git", "commit", "-m", "fix"])
        assert result == "git commit -m fix"

    def test_mixed_spaces_and_no_spaces(self):
        """Mixed elements, only quoted where needed."""
        result = format_argv(["echo", "hello world", "foo"])
        assert result == 'echo "hello world" foo'

    def test_single_element(self):
        """Single element with spaces."""
        result = format_argv(["/path/to/my script.sh"])
        assert result == '"/path/to/my script.sh"'

    def test_numeric_arguments(self):
        """Numeric values stay as-is."""
        result = format_argv(["sleep", "42"])
        assert result == "sleep 42"


class TestFormatRunProcessCommand:
    """Tests for format_run_process_command entry point."""

    def test_argv_mode(self):
        """Basic argv mode."""
        args = json.dumps({"argv": ["ls", "-la"]})
        assert format_run_process_command(args) == "ls -la"

    def test_argv_mode_with_spaces(self):
        """Argv mode with spaces in arguments."""
        args = json.dumps({"argv": ["cat", "my file.txt"]})
        assert format_run_process_command(args) == 'cat "my file.txt"'

    def test_command_line_mode(self):
        """Raw command_line passthrough."""
        args = json.dumps({"command_line": "ls -la | grep foo"})
        assert format_run_process_command(args) == "ls -la | grep foo"

    def test_command_mode(self):
        """Single command passthrough."""
        args = json.dumps({"command": "ls"})
        assert format_run_process_command(args) == "ls"

    def test_ambiguous_both_argv_and_command_line(self):
        """Should raise ValueError when both are set."""
        args = json.dumps({"command_line": "ls", "argv": ["ls"]})
        with pytest.raises(ValueError, match="Ambiguous run_process"):
            format_run_process_command(args)

    def test_missing_all_modes(self):
        """Should raise ValueError when no command found."""
        args = json.dumps({"unknown": "value"})
        with pytest.raises(ValueError, match="No command found"):
            format_run_process_command(args)

    def test_invalid_json(self):
        """Should raise JSONDecodeError for invalid JSON."""
        with pytest.raises(json.JSONDecodeError):
            format_run_process_command("not valid json")

    def test_real_trace_argv(self):
        """Full trace example from the bug report."""
        args = json.dumps({
            "argv": [
                "cat",
                "~/repos/github/g0t4/datasets/ask_traces/agents/2026-05/2026-05-30_008/1780201044-trace.json | jq 'keys'",
            ]
        })
        result = format_run_process_command(args)
        assert "jq 'keys'" in result
        assert result.startswith("cat ")

    def test_mode_legacy_key_ignored(self):
        """Legacy mode field doesn't interfere."""
        args = json.dumps({"mode": "legacy", "argv": ["echo", "hi"]})
        assert format_run_process_command(args) == "echo hi"
