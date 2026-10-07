"""Minimal inline markdown styling.

This is intentionally a small, hand-rolled subset of markdown that renders via
rich :class:`rich.text.Text` without interpreting rich markup. The goal is to
show the original text for the most part while adding a little emphasis, and to
expand the supported syntax over time.
"""

from __future__ import annotations

import re

from rich.text import Text


# A maximal run of backticks (e.g. `` ` ``, ```` `` ````, ```` ``` ````).
_BACKTICK_RUN = re.compile(r"`+")

# Bold spans: ``**text**``.
_BOLD_SPAN = re.compile(r"\*\*([^*]+)\*\*")

# Only runs of 1 or 2 backticks are valid *inline* code delimiters. A run of 3+
# is a fenced code block marker, not inline code, so it is left literal.
_MAX_INLINE_BACKTICKS = 2

# A list marker at the start of a line, e.g. ``- ``, ``* ``, ``1. ``.
_LIST_MARKER = re.compile(r"^(\s*(?:[-*+]|\d+\.)\s+)")


def _collect_code_spans(source: str) -> list[dict]:
    """Find inline code spans using the CommonMark backtick-run algorithm.

    A code span is delimited by a maximal backtick run of length ``N`` (1 or 2)
    on each side, with the content between them. This correctly handles:

    * `` `code` `` → single backtick delimiters.
    * `` `` `code` `` `` → double backtick delimiters, so a literal backtick
      inside the content (`` ` ``) is escaped and shown verbatim.

    A run of 3+ backticks is a fenced block marker, not inline code, so it is
    never treated as a delimiter. Unbalanced backticks naturally produce no
    span (the delimiter needs a matching close run).
    """
    spans: list[dict] = []
    pos = 0
    while True:
        run = _BACKTICK_RUN.search(source, pos)
        if not run:
            break
        n = len(run.group(0))
        if n > _MAX_INLINE_BACKTICKS:
            pos = run.end()
            continue

        # Find the next maximal backtick run of exactly length ``n``.
        search_pos = run.end()
        close = None
        while True:
            next_run = _BACKTICK_RUN.search(source, search_pos)
            if not next_run:
                break
            if len(next_run.group(0)) == n:
                close = next_run
                break
            search_pos = next_run.end()

        if close is None:
            pos = run.end()
            continue

        spans.append({
            "start": run.start(),
            "end": close.end(),
            "kind": "code",
            "content": source[run.end():close.start()],
            "open": run.group(0),
            "close": close.group(0),
        })
        pos = close.end()
    return spans


def _collect_bold_spans(source: str) -> list[dict]:
    """Find bold ``**text**`` spans."""
    return [
        {
            "start": match.start(),
            "end": match.end(),
            "kind": "bold",
            "content": match.group(1),
            "open": "**",
            "close": "**",
        }
        for match in _BOLD_SPAN.finditer(source)
    ]


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
    spans = _collect_code_spans(source) + _collect_bold_spans(source)
    spans.sort(key=lambda span: span["start"])

    result = Text()
    pos = 0
    for span in spans:
        if span["start"] < pos:
            # Overlapping (e.g. bold inside a code span) - the earlier span wins.
            continue
        if span["start"] > pos:
            result.append(source[pos:span["start"]], style=base_style)
        if span["kind"] == "code":
            # Inline code: keep dimmed backticks, pop the code.
            result.append(span["open"], style=backtick_style)
            result.append(span["content"], style=code_style)
            result.append(span["close"], style=backtick_style)
        elif bold_style is not None:
            # Bold: keep dimmed ``**``, pop the text.
            result.append(span["open"], style=backtick_style)
            result.append(span["content"], style=bold_style)
            result.append(span["close"], style=backtick_style)
        else:
            # Bold disabled: leave the span verbatim.
            result.append(source[span["start"]:span["end"]], style=base_style)
        pos = span["end"]
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
