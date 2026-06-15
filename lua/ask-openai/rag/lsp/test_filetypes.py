"""Tests for the filetype mapper module."""

import tempfile
from pathlib import Path

import pytest

from lsp.filetypes import (
    EXTENSION_TO_FILETYPE,
    FILENAME_TO_FILETYPE,
    SHEBANG_TO_FILETYPE,
    DEFAULT_INCLUDED_FILETYPES,
    resolve_filetype,
    get_filetype_for_extension,
    get_extensions_for_filetype,
)


class TestExtensionMapping:

    def test_unknown_extension_returns_itself(self):
        """Unmapped extensions should pass through as-is."""
        assert get_filetype_for_extension("xyz") == "xyz"
        assert get_filetype_for_extension("XYZ") == "xyz"  # case insensitive


class TestShebangDetection:
    """Test shebang-based filetype detection for extensionless files."""

    def test_unmapped_exectuable_returns_exectuable_itself(self, tmp_path):
        f = tmp_path / "bar"
        f.write_text("#!foo\nprint('hi')\n")
        assert resolve_filetype(f) == "foo"

    def test_python_shebang(self, tmp_path):
        f = tmp_path / "script"
        f.write_text("#!/usr/bin/env python3\nprint('hi')\n")
        assert resolve_filetype(f) == "py"

    def test_bash_shebang(self, tmp_path):
        f = tmp_path / "run"
        f.write_text("#!bash\necho hi\n")
        assert resolve_filetype(f) == "bash"

    def test_bin_bash_shebang(self, tmp_path):
        f = tmp_path / "run"
        f.write_text("#!/bin/bash\necho hi\n")
        assert resolve_filetype(f) == "bash"

    def test_zsh_shebang(self, tmp_path):
        f = tmp_path / "zsh_script"
        f.write_text("#!zsh\necho hi\n")
        assert resolve_filetype(f) == "zsh"

    def test_env_zsh_shebang(self, tmp_path):
        f = tmp_path / "zsh_script"
        f.write_text("#!/usr/bin/env zsh\necho hi\n")
        assert resolve_filetype(f) == "zsh"

    # TODO!FILETYPES IMPLEMENT shebang wins (after basename => filetype)
    # def test_shebang_wins_even_when_file_has_extension(self, tmp_path):
    #     f = tmp_path / "script.sh"
    #     f.write_text("#!fish\necho hi\n")
    #     assert resolve_filetype(f) == "fish"

    def test_fish_shebang(self, tmp_path):
        f = tmp_path / "fish_script"
        f.write_text("#!fish\necho hi\n")
        assert resolve_filetype(f) == "fish"

    def test_env_fish_shebang(self, tmp_path):
        f = tmp_path / "fish_script"
        # honestly one test with env + cmd should be fine... but lets keep these just cuz they are prevalent and doesn't hurt to know they work
        f.write_text("#!/usr/bin/env fish\necho hi\n")
        assert resolve_filetype(f) == "fish"

    def test_ruby_shebang(self, tmp_path):
        f = tmp_path / "rake_task"
        f.write_text("#!/usr/bin/env ruby\nputs 'hi'\n")
        assert resolve_filetype(f) == "ruby"

    def test_node_shebang(self, tmp_path):
        f = tmp_path / "cli_tool"
        f.write_text("#!/usr/bin/env node\nconsole.log('hi')\n")
        assert resolve_filetype(f) == "javascript"

    def test_perl_shebang(self, tmp_path):
        f = tmp_path / "perl_script"
        f.write_text("#!/usr/bin/env perl\nprint 'hi'\n")
        assert resolve_filetype(f) == "perl"

    def test_no_shebang_returns_none(self, tmp_path):
        f = tmp_path / "random_file"
        f.write_text("just some text\nno shebang here\n")
        assert resolve_filetype(f) is None

    def test_empty_file_returns_none(self, tmp_path):
        f = tmp_path / "empty"
        f.write_text("")
        assert resolve_filetype(f) is None

    def test_binary_file_returns_none(self, tmp_path):
        f = tmp_path / "binary"
        f.write_bytes(b"\x00\x01\x02\x03")
        assert resolve_filetype(f) is None

    def test_python_versioned_shebang(self, tmp_path):
        """python3.11 should still match python."""
        f = tmp_path / "script"
        f.write_text("#!/usr/bin/python3.11\nprint('hi')\n")
        assert resolve_filetype(f) == "py"

    def test_direct_python_path(self, tmp_path):
        """#!/usr/bin/python3 should match."""
        f = tmp_path / "script"
        f.write_text("#!/usr/bin/python3\nprint('hi')\n")
        assert resolve_filetype(f) == "py"


# ---------------------------------------------------------------------------
# Layer 4: resolve_filetype integration tests
# ---------------------------------------------------------------------------

class TestResolveFiletype:
    """Test the full resolution pipeline."""

    def test_extension_overrides_shebang(self, tmp_path):
        """If a file has an extension, shebang should be ignored."""
        # TODO!FILETYPES do I want to allow shebang to win out?
        f = tmp_path / "weird.txt"
        f.write_text("#!/usr/bin/env python3\nprint('hi')\n")
        # .txt is not in our mapping, so it returns "txt"
        assert resolve_filetype(f) == "txt"

    def test_filename_lookup_for_extensionless(self, tmp_path):
        """Extensionless known filename should resolve via filename mapping."""
        f = tmp_path / "fish_history"
        f.write_text("---\nkeys: []\n")
        assert resolve_filetype(f) == "yaml"

    def test_filename_lookup_for_dockerfile(self, tmp_path):
        f = tmp_path / "Dockerfile"
        f.write_text("FROM ubuntu\n")
        assert resolve_filetype(f) == "docker"

    def test_vim_filetype_fallback(self, tmp_path):
        """When nothing else works, vim_filetype is the fallback."""
        f = tmp_path / "mystery_file"
        f.write_text("unknown content\n")
        assert resolve_filetype(f, vim_filetype="lua") == "lua"

    def test_vim_filetype_used_when_no_extension(self):
        """vim_filetype used when file has no extension and no shebang."""
        f = Path("/no/such/path/mystery")
        assert resolve_filetype(f, vim_filetype="rust") == "rust"

    def test_path_with_yaml_extension(self):
        f = Path("/some/repo/config.yaml")
        assert resolve_filetype(f) == "yaml"

    def test_path_with_yml_extension(self):
        f = Path("/some/repo/settings.yml")
        assert resolve_filetype(f) == "yaml"

    def test_path_with_sh_extension(self):
        f = Path("/home/user/.bashrc")
        # .bashrc is in FILENAME_TO_FILETYPE, not extension-based
        # But as a path with no extension... wait, it has no extension
        assert resolve_filetype(f) == "shell"

    def test_path_with_zsh_extension(self):
        f = Path("/home/user/.zshrc")
        assert resolve_filetype(f) == "shell"
