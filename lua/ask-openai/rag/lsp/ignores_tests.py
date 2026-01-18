from pathlib import Path
import pytest

from lsp.ignores import is_ignored, use_gitignore, use_pygls_workspace

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

def test_all_paths_ignored_for_asterisk_dot_extension_pattern(tmp_root):
    use_pygls_workspace(tmp_root)

    # absolute path that IS relative to root_path
    assert is_ignored(tmp_root / "subdir/file.pyc")

    # relative path upfront
    assert is_ignored("is/relative/initially.pyc")

def test_ignore_if_not_relative_to_workspace_root_dir(tmp_root):
    use_pygls_workspace(tmp_root)
    # absolute path that IS NOT relative to root_path
    #  IOTW in a directory outside of root_path
    assert is_ignored("/foo/subdir/file.pyc")
    assert is_ignored("/foo/subdir/bar.txt")
    assert is_ignored("/venv/foo.c")

def test_literal_entry(tmp_root):
    use_pygls_workspace(tmp_root)
    assert is_ignored(tmp_root / "venv/foo.c")
    assert not is_ignored(tmp_root / "venvfoo.c")

def disable_test_listing_all_ignored_files_under_dir():
    path = Path("/Users/wesdemos/repos/github/g0t4/ask-openai.nvim")
    spec = use_gitignore(path)

    ignored_files = spec.match_tree(path)

    print("IGNORED FILES:")
    for f in ignored_files:
        print(f)
