import tempfile
from pathlib import Path

import pytest

from lsp.domains import (
    EXTENSION_TO_SEMANTIC_DOMAIN,
    BASENAME_TO_SEMANTIC_DOMAIN,
    SHEBANG_EXECUTABLE_TO_SEMANTIC_DOMAIN,
    DEFAULT_ALLOWED_SEMANTIC_DOMAINS,
    resolve_semantic_domain,
)

class TestShebangToSemanticDomainEdgeCases:
    # FYI many technically duplicated tests for sheangs,
    # - leave them so we have confidence in COMMON shebangs

    def test_unmapped_exectuable_returns_exectuable_itself(self, tmp_path):
        f = tmp_path / "bar"
        f.write_text("#!foo\nprint('hi')\n")
        assert resolve_semantic_domain(f) == "foo"

    def test_python_shebang(self, tmp_path):
        f = tmp_path / "script"
        f.write_text("#!/usr/bin/env python3\nprint('hi')\n")
        assert resolve_semantic_domain(f) == "py"

    def test_bash_shebang(self, tmp_path):
        f = tmp_path / "run"
        f.write_text("#!bash\necho hi\n")
        assert resolve_semantic_domain(f) == "bash"

    def test_bin_bash_shebang(self, tmp_path):
        f = tmp_path / "run"
        f.write_text("#!/bin/bash\necho hi\n")
        assert resolve_semantic_domain(f) == "bash"

    def test_zsh_shebang(self, tmp_path):
        f = tmp_path / "zsh_script"
        f.write_text("#!zsh\necho hi\n")
        assert resolve_semantic_domain(f) == "zsh"

    def test_env_zsh_shebang(self, tmp_path):
        f = tmp_path / "zsh_script"
        f.write_text("#!/usr/bin/env zsh\necho hi\n")
        assert resolve_semantic_domain(f) == "zsh"

    def test_fish_shebang(self, tmp_path):
        f = tmp_path / "fish_script"
        f.write_text("#!fish\necho hi\n")
        assert resolve_semantic_domain(f) == "fish"

    def test_env_fish_shebang(self, tmp_path):
        f = tmp_path / "fish_script"
        # honestly one test with env + cmd should be fine... but lets keep these just cuz they are prevalent and doesn't hurt to know they work
        f.write_text("#!/usr/bin/env fish\necho hi\n")
        assert resolve_semantic_domain(f) == "fish"

    def test_ruby_shebang(self, tmp_path):
        f = tmp_path / "rake_task"
        f.write_text("#!/usr/bin/env ruby\nputs 'hi'\n")
        assert resolve_semantic_domain(f) == "ruby"

    def test_node_shebang(self, tmp_path):
        f = tmp_path / "cli_tool"
        f.write_text("#!/usr/bin/env node\nconsole.log('hi')\n")
        assert resolve_semantic_domain(f) == "javascript"

    def test_perl_shebang(self, tmp_path):
        f = tmp_path / "perl_script"
        f.write_text("#!/usr/bin/env perl\nprint 'hi'\n")
        assert resolve_semantic_domain(f) == "perl"

    def test_no_shebang_returns_none(self, tmp_path):
        f = tmp_path / "random_file"
        f.write_text("just some text\nno shebang here\n")
        assert resolve_semantic_domain(f) is None

    def test_shebang_not_first_line(self, tmp_path):
        f = tmp_path / "wrong_shebang"
        f.write_text("some text\n#!/usr/bin/env python\n")
        assert resolve_semantic_domain(f) is None

    def test_binary_file_returns_none(self, tmp_path):
        f = tmp_path / "binary"
        f.write_bytes(b"\x00\x01\x02\x03")
        assert resolve_semantic_domain(f) is None

    def test_python_versioned_shebang(self, tmp_path):
        """python3.11 should still match python."""
        f = tmp_path / "script"
        f.write_text("#!/usr/bin/python3.11\nprint('hi')\n")
        assert resolve_semantic_domain(f) == "py"

    def test_direct_python_path(self, tmp_path):
        """#!/usr/bin/python3 should match."""
        f = tmp_path / "script"
        f.write_text("#!/usr/bin/python3\nprint('hi')\n")
        assert resolve_semantic_domain(f) == "py"

class TestResolveSemanticDomain:
    """
       Test the full resolution pipeline.
       Keep precedence tests here.
       OK to have others as well for resolvers that don't need a ton of edge cases.
    """

    def test_basename_map_wins_vs_file_extension(self, tmp_path):
        assert resolve_semantic_domain("compose.yaml") == "docker"
        assert resolve_semantic_domain("Dockerfile.j2") == "docker"

    def test_shebang_wins_vs_file_extension(self, tmp_path):
        # sh => bash normally, but here it should be fish b/c of shebang
        f = tmp_path / "script.sh"
        f.write_text("#!fish\necho hi\n")
        assert resolve_semantic_domain(f) == "fish"

    def test_basename_lookup_for_extensionless(self, tmp_path):
        f = tmp_path / "Dockerfile"
        f.write_text("FROM ubuntu\n")
        assert resolve_semantic_domain(f) == "docker"

    def test_aliased_extension_domain_lookup(self):
        f = Path("/some/repo/settings.yml")
        assert resolve_semantic_domain(f) == "yaml"

    def test_dot_files_are_recognized(self):
        # for the record, foo.ext works:
        assert resolve_semantic_domain(Path("foo.gitignore")) == "git"
        # and .ext should also work, but path.suffix doesn't do what you think so leave this test case after fixing (dropping use of suffix)
        assert resolve_semantic_domain(Path(".gitignore")) == "git"
        assert resolve_semantic_domain(Path(".rs")) == "rust"
