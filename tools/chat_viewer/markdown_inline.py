"""Minimal inline markdown styling.

This is intentionally a small, hand-rolled subset of markdown that renders via
rich :class:`rich.text.Text` without interpreting rich markup. The goal is to
show the original text for the most part while adding a little emphasis, and to
expand the supported syntax over time.
"""

from __future__ import annotations

import re

from rich.text import Text


# Single-backtick inline code spans: ```text```, or bold ``**text**``.
_INLINE_SPAN = re.compile(r"`([^`]+)`|\*\*([^*]+)\*\*")

# A list marker at the start of a line, e.g. ``- ``, ``* ``, ``1. ``.
_LIST_MARKER = re.compile(r"^(\s*(?:[-*+]|\d+\.)\s+)")


def _style_inline(
    source: str,
    *,
    base_style: str,
    code_style: str,
    backtick_style: str,
    bold_style: str | None,
) -> Text:
    """Style inline code and bold spans within a single line of ``source``.

    Inline code spans get ``code_style`` with dimmed backticks. Bold spans get
    ``bold_style`` with dimmed ``**`` delimiters. When ``bold_style`` is ``None``
    bold spans are left literal (for callers that only want inline code).
    """
    result = Text()
    pos = 0
    for match in _INLINE_SPAN.finditer(source):
        if match.start() > pos:
            result.append(source[pos:match.start()], style=base_style)
        if match.group(1) is not None:
            # Inline code: keep dimmed backticks, pop the code.
            result.append("`", style=backtick_style)
            result.append(match.group(1), style=code_style)
            result.append("`", style=backtick_style)
        elif bold_style is not None:
            # Bold: keep dimmed ``**``, pop the text.
            result.append("**", style=backtick_style)
            result.append(match.group(2), style=bold_style)
            result.append("**", style=backtick_style)
        else:
            # Bold disabled: leave the span verbatim.
            result.append(match.group(0), style=base_style)
        pos = match.end()
    if pos < len(source):
        result.append(source[pos:], style=base_style)
    return result


def _list_marker(line: str) -> str:
    """Return the leading list marker (indent + marker + space) or ``""``."""
    match = _LIST_MARKER.match(line)
    return match.group(1) if match else ""


def style_inline_code(
    source: str,
    *,
    base_style: str = "",
    code_style: str = "bold",
    backtick_style: str = "dim",
) -> Text:
    """Render ``source`` as rich ``Text`` with inline code spans emphasized.

    Single-backtick spans are converted to ``code_style`` and the surrounding
    backticks are kept but dimmed (``backtick_style``) so they recede behind the
    code. All other text is passed through verbatim (with ``base_style``) and is
    *not* interpreted as rich markup, so things like ``[dim]`` in the source are
    shown literally rather than as style tags.

    Args:
        source: The text to style.
        base_style: Rich style applied to non-code text (e.g. ``"bright_black
            italic"``).
        code_style: Rich style applied to inline code spans (default ``"bold"``).
        backtick_style: Rich style applied to the kept backtick delimiters
            (default ``"dim"``).

    Returns:
        A styled ``Text`` ready for rich rendering.
    """
    return _style_inline(
        source,
        base_style=base_style,
        code_style=code_style,
        backtick_style=backtick_style,
        bold_style=None,
    )


def style_markdown_text(
    source: str,
    *,
    base_style: str = "",
    code_style: str = "bold",
    backtick_style: str = "dim",
    bold_style: str = "bold",
) -> Text:
    """Render ``source`` with subtle markdown emphasis via rich ``Text``.

    This extends :func:`style_inline_code` with a few block-level touches that
    keep the text verbatim while letting content pop:

    * Inline code `` `code` `` → bold, with dimmed backticks.
    * Bold ``**text**`` → bold, with dimmed ``**`` delimiters.
    * Fenced code block markers (`` ``` `` lines) → dimmed, content verbatim.
    * List markers (``- ``, ``1. ``) → dimmed, content verbatim.

    Nothing is interpreted as rich markup; things like ``[dim]`` stay literal.
    """
    result = Text()
    in_fence = False
    for line in source.splitlines(keepends=True):
        body = line.rstrip("\r\n")
        stripped = body.lstrip()

        if stripped.startswith("```"):
            in_fence = not in_fence
            result.append(body, style=backtick_style)
        elif in_fence:
            result.append(body, style=base_style)
        else:
            marker = _list_marker(body)
            if marker:
                result.append(marker, style=backtick_style)
                result.append(
                    _style_inline(
                        body[len(marker):],
                        base_style=base_style,
                        code_style=code_style,
                        backtick_style=backtick_style,
                        bold_style=bold_style,
                    )
                )
            else:
                result.append(
                    _style_inline(
                        body,
                        base_style=base_style,
                        code_style=code_style,
                        backtick_style=backtick_style,
                        bold_style=bold_style,
                    )
                )

        if line.endswith("\n"):
            result.append("\n")
    return result
