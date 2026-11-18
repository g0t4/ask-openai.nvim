import pytest

from tools.chat_viewer.browser.cli import build_parser as build_browser_parser
from tools.chat_viewer.cli import build_parser as build_viewer_parser
from tools.chat_viewer.cli import build_textual_parser
from tools.pii_scanner.cli import build_parser as build_pii_parser
from tools.trace_dump.cli import build_parser as build_trace_dump_parser


def test_view_trace_parser_preserves_runtime_arguments() -> None:
    args = build_viewer_parser().parse_args(
        ["--stats", "--max-width", "0", "trace.json"]
    )

    assert args.trace_file == "trace.json"
    assert args.show_stats is True
    assert args.max_width == 0


def test_view_trace_rejects_negative_width() -> None:
    with pytest.raises(SystemExit):
        build_viewer_parser().parse_args(["--max-width", "-1"])


def test_other_entrypoint_parsers_preserve_their_grammar() -> None:
    assert build_textual_parser().parse_args(["trace.json"]).trace_file == "trace.json"
    assert build_browser_parser().parse_args(["agents"]).from_dir == "agents"
    assert (
        build_trace_dump_parser().parse_args(["--plain-text", "trace.json"]).plain_text
    )

    pii = build_pii_parser().parse_args(
        ["--extract-paths", "--threshold", "0.8", "trace.json"]
    )
    assert pii.extract_paths is True
    assert pii.threshold == 0.8
    assert pii.target == "trace.json"
