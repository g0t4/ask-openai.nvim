"""Tests for the split_h2_markdown_sections utility function.

The tests verify that the function correctly splits markdown text into sections
based on H2 headers (lines starting with ``## ``). The function is imported from
the ``tools.chat_viewer.markdown_utils`` module.
"""

# Import directly from the ``chat_viewer`` package, which is a top-level module
# after adding an ``__init__`` file in ``tools`` and ``tools/chat_viewer``.
# Ensure the repository root is on ``sys.path`` so that the local ``tools``
# package is imported instead of any similarly‑named third‑party package.
import os
import sys

repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if repo_root not in sys.path:
    sys.path.insert(0, repo_root)

from tools.chat_viewer.markdown_utils import split_h2_markdown_sections


def test_split_h2_markdown_sections_basic() -> None:
    text = (
        "Intro line\n"
        "## Header One\n"
        "Line 1\n"
        "Line 2\n"
        "## Header Two\n"
        "Another line"
    )
    sections = list(split_h2_markdown_sections(text))
    # The original implementation yields any content before the first H2 header as a
    # separate section, followed by the sections that start with ``## ``.
    assert sections == [
        "Intro line",
        "## Header One\nLine 1\nLine 2",
        "## Header Two\nAnother line",
    ]


def test_split_h2_markdown_sections_no_header() -> None:
    text = "Just some text\nwith multiple lines\nand no header."
    sections = list(split_h2_markdown_sections(text))
    assert sections == ["Just some text\nwith multiple lines\nand no header."]
