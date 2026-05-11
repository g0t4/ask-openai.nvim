import os
import sys

from .markdown_utils import split_h2_markdown_sections

def test_split_h2_markdown_sections_basic() -> None:
    text = ("Intro line\n"
            "## Header One\n"
            "Line 1\n"
            "Line 2\n"
            "## Header Two\n"
            "Another line")
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
