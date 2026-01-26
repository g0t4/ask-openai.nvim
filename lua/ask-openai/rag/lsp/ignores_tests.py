from pathlib import Path
import pytest
import rich

import lsp.ignores
from lsp.ignores import _is_gitignored, setup_config
from lsp.config import Config

@pytest.fixture
def tmp_root(tmp_path):

    # * love that pytest has tmp_path dep => makes a temp dir and cleans up after test
    #  and then tmp_root here is an extension of that that becomes a test dependency (see cases below)
    # print(tmp_path)  # scoped per test too (by test name!)
    # ends with: pytest-of-wesdemos/pytest-20/test_is_ignored0

    # Create a temporary directory structure with .gitignore
    root = tmp_path / "repo"
    root.mkdir()

    # Create .gitignore file with some patterns
    gitignore = root / ".gitignore"
    gitignore.write_text("""
    *.log
    /venv/
    *.pyc
    """)

    return root

def test_package_lock_is_ignored(tmp_root):
    setup_config(tmp_root, Config.default())
    rich.print("\n[red bold]tmp_root", tmp_root, "\n")

    # * careful with path that is ignored for other reasons
    assert _is_gitignored(tmp_root / "package-lock.json")
    assert _is_gitignored(tmp_root / "uv.lock")

def test_all_paths_ignored_for_asterisk_dot_extension_pattern(tmp_root):
    setup_config(tmp_root, Config.default())

    # absolute path that IS relative to root_path
    assert _is_gitignored(tmp_root / "subdir/file.pyc")

    # relative path upfront
    assert _is_gitignored("is/relative/initially.pyc")

def test_ignore_if_not_relative_to_workspace_root_dir(tmp_root):
    setup_config(tmp_root, Config.default())
    # absolute path that IS NOT relative to root_path
    #  IOTW in a directory outside of root_path
    assert _is_gitignored("/foo/subdir/file.pyc")
    assert _is_gitignored("/foo/subdir/bar.txt")
    assert _is_gitignored("/venv/foo.c")

def test_literal_entry(tmp_root):
    setup_config(tmp_root, Config.default())
    assert _is_gitignored(tmp_root / "venv/foo.c")
    assert not _is_gitignored(tmp_root / "venvfoo.c")

def disabled_manual_test_listing_all_ignored_files_under_dir():
    path = Path("/Users/wesdemos/repos/github/g0t4/ask-openai.nvim")
    setup_config(path, Config.default())

    assert lsp.ignores.gitignore_spec
    spec = lsp.ignores.gitignore_spec
    ignored_files = spec.match_tree(path)

    print("IGNORED FILES:")
    for f in ignored_files:
        print(f)
