"""Tests for ``tools.chat_viewer.markdown_inline``."""

from rich.text import Text
from rich.style import Style

from tools.chat_viewer.markdown_inline import style_inline_code


def bold_spans(text: Text) -> list[str]:
    """Return the plain text of each bold span in ``text``."""
    return [
        text.plain[span.start:span.end]
        for span in text.spans
        if _span_style(span).bold
    ]


def _span_style(span: Text) -> Style:
    """Return a ``Style`` object for a span (style may be str or ``Style``)."""
    style = span.style
    return Style.parse(style) if isinstance(style, str) else style


def test_basic_inline_code_is_bolded() -> None:
    styled = style_inline_code("Use `foo` here")
    assert styled.plain == "Use foo here"
    assert bold_spans(styled) == ["foo"]


def test_multiple_inline_code_spans() -> None:
    styled = style_inline_code("Call `run_process` with `cwd` set")
    assert styled.plain == "Call run_process with cwd set"
    assert bold_spans(styled) == ["run_process", "cwd"]


def test_no_backticks_passes_through() -> None:
    source = "Just some plain text with no code."
    styled = style_inline_code(source)
    assert styled.plain == source
    assert bold_spans(styled) == []


def test_code_at_start_and_end() -> None:
    styled = style_inline_code("`start` middle `end`")
    assert styled.plain == "start middle end"
    assert bold_spans(styled) == ["start", "end"]


def test_code_content_not_treated_as_rich_markup() -> None:
    # Rich markup like ``[dim]`` must be shown literally, not interpreted.
    styled = style_inline_code("See `[dim]x` for details")
    assert styled.plain == "See [dim]x for details"
    assert bold_spans(styled) == ["[dim]x"]


def test_unmatched_backtick_stays_literal() -> None:
    # An odd, unmatched backtick is not a valid span and is kept verbatim.
    styled = style_inline_code("a ` b")
    assert styled.plain == "a ` b"
    assert bold_spans(styled) == []


def test_empty_code_span_is_not_a_span() -> None:
    # `` (empty content) is not matched by the single-backtick pattern.
    styled = style_inline_code("keep ``")
    assert styled.plain == "keep ``"
    assert bold_spans(styled) == []


def test_base_style_is_applied_to_non_code_text() -> None:
    styled = style_inline_code("x `y` z", base_style="bright_black italic")
    assert styled.plain == "x y z"
    # The code span is bold, and the surrounding base text carries base style.
    code_span = next(s for s in styled.spans if _span_style(s).bold)
    assert styled.plain[code_span.start:code_span.end] == "y"
    base_span = next(s for s in styled.spans if not _span_style(s).bold)
    assert styled.plain[base_span.start:base_span.end] == "x "
    assert _span_style(base_span).italic is True


def test_custom_code_style() -> None:
    styled = style_inline_code("`run`", code_style="bold italic")
    assert styled.plain == "run"
    span = styled.spans[0]
    assert _span_style(span).bold is True
    assert _span_style(span).italic is True
