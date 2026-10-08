"""Tests for ``tools.chat_viewer.markdown_inline``."""

from rich.text import Text
from rich.style import Style

from tools.chat_viewer.markdown_inline import style_inline_code, style_markdown_text


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


def dim_spans(text: Text) -> list[str]:
    """Return the plain text of each dimmed span in ``text``."""
    return [
        text.plain[span.start:span.end]
        for span in text.spans
        if _span_style(span).dim
    ]


def test_basic_inline_code_is_bolded() -> None:
    styled = style_inline_code("Use `foo` here")
    assert styled.plain == "Use `foo` here"
    assert bold_spans(styled) == ["foo"]


def test_multiple_inline_code_spans() -> None:
    styled = style_inline_code("Call `run_process` with `cwd` set")
    assert styled.plain == "Call `run_process` with `cwd` set"
    assert bold_spans(styled) == ["run_process", "cwd"]


def test_no_backticks_passes_through() -> None:
    source = "Just some plain text with no code."
    styled = style_inline_code(source)
    assert styled.plain == source
    assert bold_spans(styled) == []


def test_code_at_start_and_end() -> None:
    styled = style_inline_code("`start` middle `end`")
    assert styled.plain == "`start` middle `end`"
    assert bold_spans(styled) == ["start", "end"]


def test_code_content_not_treated_as_rich_markup() -> None:
    # Rich markup like ``[dim]`` must be shown literally, not interpreted.
    styled = style_inline_code("See `[dim]x` for details")
    assert styled.plain == "See `[dim]x` for details"
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
    assert styled.plain == "x `y` z"
    # The code span is bold, and the surrounding base text carries base style.
    code_span = next(s for s in styled.spans if _span_style(s).bold)
    assert styled.plain[code_span.start:code_span.end] == "y"
    base_span = next(s for s in styled.spans if not _span_style(s).bold)
    assert styled.plain[base_span.start:base_span.end] == "x "
    assert _span_style(base_span).italic is True


def test_custom_code_style() -> None:
    styled = style_inline_code("`run`", code_style="bold italic")
    assert styled.plain == "`run`"
    code_span = next(s for s in styled.spans if _span_style(s).bold)
    assert styled.plain[code_span.start:code_span.end] == "run"
    assert _span_style(code_span).italic is True


def test_backticks_are_dimmed() -> None:
    styled = style_inline_code("Use `foo` here")
    assert dim_spans(styled) == ["`", "`"]
    assert bold_spans(styled) == ["foo"]


def test_custom_backtick_style() -> None:
    styled = style_inline_code(
        "`run`",
        code_style="bold bright_black italic",
        backtick_style="dim bright_black italic",
    )
    assert styled.plain == "`run`"
    backtick_span = next(s for s in styled.spans if _span_style(s).dim)
    assert styled.plain[backtick_span.start:backtick_span.end] == "`"
    assert _span_style(backtick_span).italic is True


def test_markdown_bold_is_bolded_with_dimmed_delimiters() -> None:
    styled = style_markdown_text("**Important** step")
    assert styled.plain == "**Important** step"
    assert bold_spans(styled) == ["Important"]
    assert dim_spans(styled) == ["**", "**"]


def test_markdown_combines_inline_code_and_bold() -> None:
    styled = style_markdown_text("Use `run` then **go**")
    assert styled.plain == "Use `run` then **go**"
    assert bold_spans(styled) == ["run", "go"]


def test_markdown_inline_code_only_keeps_bold_literal() -> None:
    # style_inline_code does not process ``**bold**``.
    styled = style_inline_code("**keep** `code`")
    assert styled.plain == "**keep** `code`"
    assert bold_spans(styled) == ["code"]


def test_markdown_fence_markers_are_dimmed_content_verbatim() -> None:
    source = "before\n```lua\nlocal x = 1\n```\nafter"
    styled = style_markdown_text(source)
    assert styled.plain == source
    # The two fence lines are dimmed.
    assert dim_spans(styled) == ["```lua", "```"]
    # Code content is not styled (no bold/code spans inside the fence).
    assert bold_spans(styled) == []


def test_markdown_fence_content_not_inline_styled() -> None:
    source = "```\n`not_inline` and **not_bold**\n```"
    styled = style_markdown_text(source)
    assert styled.plain == source
    assert bold_spans(styled) == []


def test_markdown_list_markers_are_dimmed() -> None:
    source = "- first item\n1. second item\n* third item"
    styled = style_markdown_text(source)
    assert styled.plain == source
    assert dim_spans(styled) == ["- ", "1. ", "* "]


def test_markdown_list_content_still_inline_styled() -> None:
    styled = style_markdown_text("- run `apply_patch`")
    assert styled.plain == "- run `apply_patch`"
    assert "- " in dim_spans(styled)
    assert bold_spans(styled) == ["apply_patch"]


def test_markdown_does_not_treat_star_args_as_list() -> None:
    styled = style_markdown_text("*args unpacked")
    assert styled.plain == "*args unpacked"
    assert dim_spans(styled) == []


def test_markdown_multiline_preserves_structure() -> None:
    source = "Line one\n1. item\nLine three"
    styled = style_markdown_text(source)
    assert styled.plain == source


def test_triple_backticks_on_one_line_not_styled() -> None:
    # Two fence runs on the same line are not inline code; leave them literal.
    source = (
        "first line is ``` with optional language... and strip ``` on last line"
    )
    styled = style_markdown_text(source)
    assert styled.plain == source
    assert bold_spans(styled) == []


def test_double_backtick_escaping() -> None:
    # `` `code` `` uses double backticks to escape a literal backtick inside.
    source = "like `` `code` ``."
    styled = style_markdown_text(source)
    # CommonMark strips the single padding space on each side of the content,
    # so the dimmed delimiters sit flush against the inner backticks.
    assert styled.plain == "like ```code```."
    # The content (including the literal single backticks) is bolded.
    assert bold_spans(styled) == ["`code`"]
    # The double backtick delimiters are dimmed.
    assert "``" in dim_spans(styled)


def test_unbalanced_single_backticks_not_styled() -> None:
    # A lone backtick with no matching close is not a code span.
    styled = style_markdown_text("or single `")
    assert styled.plain == "or single `"
    assert bold_spans(styled) == []


def test_triple_backtick_run_does_not_pair_with_single() -> None:
    # A 3-backtick run is not a valid single-backtick delimiter, so it never
    # pairs with a lone backtick to form a span.
    source = "text ``` then `x`"
    styled = style_markdown_text(source)
    assert styled.plain == source
    # Only the isolated `` `x` `` pair forms a span.
    assert bold_spans(styled) == ["x"]


def test_escaping_example_from_trace() -> None:
    source = "the model wraps the whole completion in single backticks like `` `code` ``."
    styled = style_markdown_text(source)
    # Padding spaces are stripped per CommonMark.
    assert styled.plain == (
        "the model wraps the whole completion in single backticks like ```code```."
    )
    assert bold_spans(styled) == ["`code`"]


def test_commonmark_strips_surrounding_spaces() -> None:
    styled = style_markdown_text("a `` `code` `` b")
    assert styled.plain == "a ```code``` b"
    assert bold_spans(styled) == ["`code`"]


def test_commonmark_keeps_all_spaces_content() -> None:
    # Content that is entirely spaces is not stripped.
    styled = style_markdown_text("`   `")
    assert styled.plain == "`   `"
    assert bold_spans(styled) == ["   "]
