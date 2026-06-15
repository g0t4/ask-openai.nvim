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


# ---------------------------------------------------------------------------
# Layer 1: Extension mapping tests
# ---------------------------------------------------------------------------

class TestExtensionMapping:
    """Test that extensions map to correct canonical filetypes."""

    def test_yaml_yml_both_map_to_yaml(self):
        assert EXTENSION_TO_FILETYPE["yaml"] == "yaml"
        assert EXTENSION_TO_FILETYPE["yml"] == "yaml"

    def test_shell_family_maps_to_shell(self):
        for ext in ("sh", "bash", "zsh", "fish"):
            assert EXTENSION_TO_FILETYPE[ext] == "shell", f"{ext} should map to shell"

    def test_cpp_variants_map_to_cpp(self):
        for ext in ("cpp", "cc", "cxx", "hpp", "hh", "hxx"):
            assert EXTENSION_TO_FILETYPE[ext] == "cpp", f"{ext} should map to cpp"

    def test_objc_variants_map_to_objc(self):
        for ext in ("m", "mm"):
            assert EXTENSION_TO_FILETYPE[ext] == "objc"

    def test_typescript_variants(self):
        assert EXTENSION_TO_FILETYPE["ts"] == "typescript"
        assert EXTENSION_TO_FILETYPE["tsx"] == "typescript"

    def test_javascript_variants(self):
        assert EXTENSION_TO_FILETYPE["js"] == "javascript"
        assert EXTENSION_TO_FILETYPE["jsx"] == "javascript"

    def test_python_variants(self):
        for ext in ("py", "pyw", "pyi"):
            assert EXTENSION_TO_FILETYPE[ext] == "py"

    def test_html_variants(self):
        for ext in ("html", "htm"):
            assert EXTENSION_TO_FILETYPE[ext] == "html"

    def test_markdown_variants(self):
        for ext in ("md", "mdx", "mkd"):
            assert EXTENSION_TO_FILETYPE[ext] == "markdown"

    def test_diff_variants(self):
        for ext in ("diff", "patch"):
            assert EXTENSION_TO_FILETYPE[ext] == "diff"

    def test_css_preprocessor_variants(self):
        assert EXTENSION_TO_FILETYPE["scss"] == "scss"
        assert EXTENSION_TO_FILETYPE["sass"] == "scss"
        assert EXTENSION_TO_FILETYPE["less"] == "less"

    def test_unknown_extension_returns_itself(self):
        """Unmapped extensions should pass through as-is."""
        assert get_filetype_for_extension("xyz") == "xyz"
        assert get_filetype_for_extension("XYZ") == "xyz"  # case insensitive


# ---------------------------------------------------------------------------
# Layer 2: Filename lookup tests
# ---------------------------------------------------------------------------

class TestFilenameMapping:
    """Test that explicit filenames map to correct filetypes."""

    def test_makefile_variants(self):
        for name in ("Makefile", "makefile", "GNUmakefile"):
            assert FILENAME_TO_FILETYPE[name] == "make"

    def test_dockerfile(self):
        assert FILENAME_TO_FILETYPE["Dockerfile"] == "docker"
        assert FILENAME_TO_FILETYPE["Containerfile"] == "docker"

    def test_gitignore_is_diff(self):
        assert FILENAME_TO_FILETYPE[".gitignore"] == "diff"

    def test_fish_history_is_yaml(self):
        assert FILENAME_TO_FILETYPE["fish_history"] == "yaml"

    def test_env_is_ini(self):
        assert FILENAME_TO_FILETYPE[".env"] == "ini"

    def test_editorconfig_is_ini(self):
        assert FILENAME_TO_FILETYPE[".editorconfig"] == "ini"

    def test_gitconfig_is_ini(self):
        assert FILENAME_TO_FILETYPE[".gitconfig"] == "ini"

    def test_bash_zsh_rc_files(self):
        for name in (".bashrc", ".bash_profile", ".zshrc", ".profile"):
            assert FILENAME_TO_FILETYPE[name] == "shell"

    def test_cargo_files_are_toml(self):
        assert FILENAME_TO_FILETYPE["Cargo.toml"] == "toml"
        assert FILENAME_TO_FILETYPE["Cargo.lock"] == "toml"

    def test_package_json_is_json(self):
        assert FILENAME_TO_FILETYPE["package.json"] == "json"
        assert FILENAME_TO_FILETYPE["package-lock.json"] == "json"

    def test_gemfile_is_ruby(self):
        assert FILENAME_TO_FILETYPE["Gemfile"] == "ruby"

    def test_go_mod_is_go(self):
        assert FILENAME_TO_FILETYPE["go.mod"] == "go"


# ---------------------------------------------------------------------------
# Layer 3: Shebang detection tests
# ---------------------------------------------------------------------------

class TestShebangDetection:
    """Test shebang-based filetype detection for extensionless files."""

    def test_python_shebang(self, tmp_path):
        f = tmp_path / "script"
        f.write_text("#!/usr/bin/env python3\nprint('hi')\n")
        assert resolve_filetype(f) == "py"

    def test_bash_shebang(self, tmp_path):
        f = tmp_path / "run"
        f.write_text("#!/bin/bash\necho hi\n")
        assert resolve_filetype(f) == "shell"

    def test_zsh_shebang(self, tmp_path):
        f = tmp_path / "zsh_script"
        f.write_text("#!/usr/bin/env zsh\necho hi\n")
        assert resolve_filetype(f) == "shell"

    def test_fish_shebang(self, tmp_path):
        f = tmp_path / "fish_script"
        f.write_text("#!/usr/bin/env fish\necho hi\n")
        assert resolve_filetype(f) == "shell"

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
        f = tmp_path / "weird.txt"
        f.write_text("#!/usr/bin/env python3\nprint('hi')\n")
        # .txt is not in our mapping, so it returns "txt"
        assert resolve_filetype(f) == "txt"

    def test_extension_takes_precedence_over_filename(self):
        """Extension always wins over filename lookup."""
        # A file named "Makefile.js" should be javascript, not make
        f = Path("/some/path/Makefile.js")
        assert resolve_filetype(f) == "javascript"

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


# ---------------------------------------------------------------------------
# DEFAULT_INCLUDES tests
# ---------------------------------------------------------------------------

class TestDefaultIncludes:
    """Test that DEFAULT_INCLUDES uses canonical filetypes."""

    def test_no_raw_extensions_in_default_includes(self):
        """DEFAULT_INCLUDES should only contain canonical filetypes, not raw extensions."""
        # If yml is in DEFAULT_INCLUDES, that's a bug — it should be "yaml"
        assert "yml" not in DEFAULT_INCLUDED_FILETYPES
        assert "sh" not in DEFAULT_INCLUDED_FILETYPES
        assert "fish" not in DEFAULT_INCLUDED_FILETYPES
        assert "zsh" not in DEFAULT_INCLUDED_FILETYPES
        assert "cc" not in DEFAULT_INCLUDED_FILETYPES
        assert "hpp" not in DEFAULT_INCLUDED_FILETYPES

    def test_canonical_filetypes_present(self):
        """Canonical filetypes should be present."""
        assert "yaml" in DEFAULT_INCLUDED_FILETYPES
        assert "shell" in DEFAULT_INCLUDED_FILETYPES
        assert "cpp" in DEFAULT_INCLUDED_FILETYPES
        assert "py" in DEFAULT_INCLUDED_FILETYPES
        assert "lua" in DEFAULT_INCLUDED_FILETYPES

    def test_no_duplicate_canonical_types(self):
        """No canonical filetype should appear twice."""
        assert len(DEFAULT_INCLUDED_FILETYPES) == len(set(DEFAULT_INCLUDED_FILETYPES))


# ---------------------------------------------------------------------------
# get_extensions_for_filetype tests
# ---------------------------------------------------------------------------

class TestExtensionsForFiletype:
    """Test the set-based reverse lookup."""

    def test_yaml_extensions(self):
        exts = get_extensions_for_filetype("yaml")
        assert exts == {"yaml", "yml"}

    def test_shell_extensions(self):
        exts = get_extensions_for_filetype("shell")
        assert exts == {"sh", "bash", "zsh", "fish"}

    def test_c_extensions(self):
        exts = get_extensions_for_filetype("c")
        assert exts == {"c", "h"}

    def test_objc_extensions(self):
        exts = get_extensions_for_filetype("objc")
        assert exts == {"m", "mm"}
