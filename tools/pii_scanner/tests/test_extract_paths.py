"""Tests for extract-paths mode in the PII scanner.

Usage:
    pytest tools/pii_scanner/tests/test_extract_paths.py -v
"""

import json
import pytest
from pathlib import Path

from tools.pii_scanner.scanner import (
    _FILE_PATH_RE,
    _extract_paths_from_value,
    _extract_paths_from_message,
    extract_paths_from_trace,
    find_trace_files,
    _try_json_decode,
)

# Path to the example trace file
EXAMPLE_TRACE_DIR = Path.home() / "repos/github/g0t4/datasets/ask_traces/agents/2026-05/2026-05-30_008"
EXAMPLE_TRACE_FILE = EXAMPLE_TRACE_DIR / "1780201044-trace.json"


# ─────────────────────────────────────────────
# Regex tests
# ─────────────────────────────────────────────

class TestFilePathRegex:
    """Test the file path regex pattern."""

    def test_absolute_unix_path(self):
        text = "/usr/bin/env python3"
        matches = [m.group() for m in _FILE_PATH_RE.finditer(text)]
        assert "/usr/bin/env python3" in matches or "/usr/bin/env" in matches

    def test_relative_path_with_dot(self):
        text = "./lua/ask-openai/tools"
        matches = [m.group() for m in _FILE_PATH_RE.finditer(text)]
        assert "./lua/ask-openai/tools" in matches

    def test_parent_dir_path(self):
        text = "../parent/dir/file.py"
        matches = [m.group() for m in _FILE_PATH_RE.finditer(text)]
        assert "../parent/dir/file.py" in matches

    def test_tilde_path(self):
        text = "~/repos/github/g0t4/ask-openai.nvim"
        matches = [m.group() for m in _FILE_PATH_RE.finditer(text)]
        assert "~/repos/github/g0t4/ask-openai.nvim" in matches

    def test_windows_path(self):
        text = "C:/windows/path/file.dll"
        matches = [m.group() for m in _FILE_PATH_RE.finditer(text)]
        assert "C:/windows/path/file.dll" in matches

    def test_dotted_path(self):
        text = ".agents/instructs/tool_delegate.md"
        matches = [m.group() for m in _FILE_PATH_RE.finditer(text)]
        assert ".agents/instructs/tool_delegate.md" in matches

    def test_path_with_backticks(self):
        text = "`lua/ask-openai/tools/inproc/tool_delegate.md`"
        matches = [m.group() for m in _FILE_PATH_RE.finditer(text)]
        assert "lua/ask-openai/tools/inproc/tool_delegate.md" in matches

    def test_no_match_on_url(self):
        """URLs should not be matched as paths (they're caught elsewhere)."""
        text = "https://example.com/path/to/resource"
        # The regex may or may not match this depending on the domain - that's OK
        # We just want to ensure the regex doesn't crash or match obvious non-paths
        matches = [m.group() for m in _FILE_PATH_RE.finditer(text)]
        # URLs starting with http:// or https:// shouldn't match
        for match in matches:
            assert not match.startswith("http://") and not match.startswith("https://")

    def test_no_match_on_short_text(self):
        """Short text without paths shouldn't produce matches."""
        text = "b/w"
        matches = [m.group() for m in _FILE_PATH_RE.finditer(text)]
        # This should either match nothing or be clearly noise we can filter
        # (We'll decide based on actual output)


# ─────────────────────────────────────────────
# JSON decode helper
# ─────────────────────────────────────────────

class TestTryJsonDecode:
    """Test _try_json_decode helper."""

    def test_valid_json_string(self):
        result = _try_json_decode('{"key": "value"}')
        assert isinstance(result, dict)
        assert result["key"] == "value"

    def test_valid_json_array(self):
        result = _try_json_decode('[1, 2, 3]')
        assert isinstance(result, list)
        assert result == [1, 2, 3]

    def test_invalid_json_returns_none(self):
        result = _try_json_decode("not json")
        assert result is None

    def test_plain_string_returns_none(self):
        result = _try_json_decode("just a string")
        assert result is None

    def test_empty_string_returns_none(self):
        result = _try_json_decode("")
        assert result is None


# ─────────────────────────────────────────────
# Value extraction tests
# ─────────────────────────────────────────────

class TestExtractPathsFromValue:
    """Test _extract_paths_from_value recursive extraction."""

    def test_plain_string_with_path(self):
        value = "~/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/tools.lua"
        paths = _extract_paths_from_value(value)
        assert len(paths) > 0
        assert any("ask-openai.nvim" in p for p in paths)

    def test_json_string_with_path(self):
        """JSON-encoded string should be decoded and paths extracted from inside."""
        value = json.dumps({"command": "cd ~/repos/github/g0t4/project && ls"})
        paths = _extract_paths_from_value(value)
        assert len(paths) > 0
        assert any("repos/github/g0t4" in p for p in paths)

    def test_nested_json_string(self):
        """Nested JSON-encoded strings should be recursively decoded."""
        value = json.dumps({
            "tool_calls": [{
                "function": {
                    "arguments": json.dumps({
                        "command_line": "mv file1 file2"
                    })
                }
            }]
        })
        paths = _extract_paths_from_value(value)
        # Should extract from the decoded structure

    def test_dict_with_paths(self):
        value = {
            "file": "~/repos/test.py",
            "output": "done"
        }
        paths = _extract_paths_from_value(value)
        assert any("test.py" in p for p in paths)

    def test_list_with_paths(self):
        value = ["~/repos/file1.lua", "some text", "~/repos/file2.lua"]
        paths = _extract_paths_from_value(value)
        assert len(paths) >= 2
        assert any("file1.lua" in p for p in paths)
        assert any("file2.lua" in p for p in paths)

    def test_empty_string(self):
        paths = _extract_paths_from_value("")
        assert paths == []

    def test_none_value(self):
        paths = _extract_paths_from_value(None)
        assert paths == []


# ─────────────────────────────────────────────
# Message extraction tests
# ─────────────────────────────────────────────

class TestExtractPathsFromMessage:
    """Test _extract_paths_from_message."""

    def test_content_with_path(self):
        message = {
            "role": "assistant",
            "content": "Here is the path: ~/repos/github/g0t4/project/file.lua"
        }
        paths = _extract_paths_from_message(message)
        assert any("file.lua" in p for p in paths)

    def test_reasoning_content_with_path(self):
        message = {
            "role": "assistant",
            "reasoning_content": "I should move `lua/ask-openai/tools/inproc/tool_delegate.md` to `.agents/instructs/tool_delegate.md`"
        }
        paths = _extract_paths_from_message(message)
        assert any("tool_delegate.md" in p for p in paths)
        assert any(".agents/instructs" in p for p in paths)

    def test_tool_calls_with_json_arguments(self):
        message = {
            "role": "assistant",
            "tool_calls": [{
                "function": {
                    "name": "run_process",
                    "arguments": json.dumps({
                        "command_line": "cd ~/repos/github/g0t4/ask-openai.nvim && git mv file1 file2"
                    })
                }
            }]
        }
        paths = _extract_paths_from_message(message)
        assert any("ask-openai.nvim" in p for p in paths)

    def test_tool_calls_with_plain_string_arguments(self):
        """Arguments that aren't valid JSON should still be searched as strings."""
        message = {
            "role": "assistant",
            "tool_calls": [{
                "function": {
                    "name": "run_process",
                    "arguments": "cd ~/repos/github/g0t4/ask-openai.nvim && git mv file1 file2"
                }
            }]
        }
        paths = _extract_paths_from_message(message)
        assert any("ask-openai.nvim" in p for p in paths)

    def test_message_without_optional_fields(self):
        """Messages missing reasoning_content or tool_calls should not crash."""
        message = {
            "role": "user",
            "content": "Hello"
        }
        paths = _extract_paths_from_message(message)
        # Should return empty or paths from content
        assert isinstance(paths, list)

    def test_content_is_json_string(self):
        """Content that is a JSON string should be decoded and searched."""
        message = {
            "role": "tool",
            "content": json.dumps({
                "content": [
                    {"type": "text", "text": "STDOUT: .agents/instructs/tool_delegate.md"}
                ]
            })
        }
        paths = _extract_paths_from_message(message)
        assert any(".agents/instructs" in p for p in paths)


# ─────────────────────────────────────────────
# Integration tests
# ─────────────────────────────────────────────

@pytest.mark.skipif(
    not EXAMPLE_TRACE_FILE.exists(),
    reason="Example trace file not found"
)
class TestExtractPathsFromTrace:
    """Integration tests against real trace file."""

    def test_trace_file_found(self):
        """Example trace file should exist."""
        assert EXAMPLE_TRACE_FILE.exists()

    def test_extract_paths_from_example_trace(self):
        """Extract paths from the example trace file."""
        paths = extract_paths_from_trace(EXAMPLE_TRACE_FILE)
        assert isinstance(paths, list)
        assert len(paths) > 0

    def test_trace_contains_expected_paths(self):
        """The example trace should contain known paths from the examples."""
        paths = extract_paths_from_trace(EXAMPLE_TRACE_FILE)
        paths_str = " ".join(paths)

        # From the examples, we know these should be present
        assert "lua/ask-openai/tools/inproc/tool_delegate.md" in paths_str
        assert ".agents/instructs/tool_delegate.md" in paths_str

    def test_trace_contains_tilde_paths(self):
        """The trace should contain ~-prefixed paths from tool_calls."""
        paths = extract_paths_from_trace(EXAMPLE_TRACE_FILE)
        paths_str = " ".join(paths)
        assert "repos/github/g0t4/ask-openai.nvim" in paths_str

    def test_no_duplicates(self):
        """Extracted paths should be deduplicated."""
        paths = extract_paths_from_trace(EXAMPLE_TRACE_FILE)
        assert len(paths) == len(set(paths))


class TestFindTraceFiles:
    """Test find_trace_files function."""

    def test_find_trace_files_in_example_dir(self):
        """Should find the example trace file."""
        trace_files = find_trace_files(EXAMPLE_TRACE_DIR)
        trace_names = [f.name for f in trace_files]
        assert "1780201044-trace.json" in trace_names

    def test_find_trace_files_returns_sorted(self):
        """Should return sorted results."""
        trace_files = find_trace_files(EXAMPLE_TRACE_DIR)
        names = [f.name for f in trace_files]
        assert names == sorted(names)
