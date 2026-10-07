"""Minimal inline markdown styling.

This is intentionally a small, hand-rolled subset of markdown that renders via
rich :class:`rich.text.Text` without interpreting rich markup. The goal is to
show the original text for the most part while adding a little emphasis, and to
expand the supported syntax over time.
"""

from __future__ import annotations

import re

from rich.text import Text


# Single-backtick inline code spans: ```text``` (non-greedy, at least one char).
_INLINE_CODE_PATTERN = re.compile(r"`([^`]+)`")


def style_inline_code(
    source: str,
    *,
    base_style: str = "",
    code_style: str = "bold",
) -> Text:
    """Render ``source`` as rich ``Text`` with inline code spans emphasized.

    Single-backtick spans are converted to ``code_style`` and the surrounding
    backticks are dropped. All other text is passed through verbatim (with
    ``base_style``) and is *not* interpreted as rich markup, so things like
    ``[dim]`` in the source are shown literally rather than as style tags.

    Args:
        source: The text to style.
        base_style: Rich style applied to non-code text (e.g. ``"bright_black
            italic"``).
        code_style: Rich style applied to inline code spans (default ``"bold"``).

    Returns:
        A styled ``Text`` ready for rich rendering.
    """
    result = Text()
    pos = 0
    for match in _INLINE_CODE_PATTERN.finditer(source):
        if match.start() > pos:
            result.append(source[pos:match.start()], style=base_style)
        result.append(match.group(1), style=code_style)
        pos = match.end()
    if pos < len(source):
        result.append(source[pos:], style=base_style)
    return result
