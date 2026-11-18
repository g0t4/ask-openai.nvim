"""Lightweight parser definitions for the chat viewer commands."""

from __future__ import annotations

import argparse
from dataclasses import dataclass


def parse_max_width(value: str) -> int:
    width = int(value)
    if width < 0:
        raise argparse.ArgumentTypeError(
            "max width must be non-negative (0 means full width)"
        )
    return width


@dataclass
class ChatViewerArgs(argparse.Namespace):
    """Strongly-typed command-line arguments for the chat viewer."""

    trace_file: str | None = None
    watch: str | None = None
    show_all: bool = False
    show_stats: bool = False
    max_width: int = 160


@dataclass
class TextualViewerArgs(argparse.Namespace):
    """Strongly-typed command-line arguments for the textual viewer."""

    trace_file: str | None = None
    max_width: int = 160


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="view_trace", description="View chat traces")
    parser.add_argument(
        "trace_file",
        nargs="?",
        default=None,
        help="path to trace file (stdin when piped; live agent viewer when omitted)",
    )
    parser.add_argument(
        "--watch",
        nargs="?",
        const="",
        metavar="DIRECTORY",
        help=(
            "follow the newest agent trace in DIRECTORY "
            "(default: Neovim agent state directory)"
        ),
    )
    parser.add_argument(
        "--all",
        action="store_true",
        dest="show_all",
        help="show all content (no exclusions)",
    )
    parser.add_argument(
        "--stats",
        action=argparse.BooleanOptionalAction,
        dest="show_stats",
        help="show per-message timing stats (default: off; use --no-stats to disable)",
    )
    parser.add_argument(
        "--max-width",
        type=parse_max_width,
        default=160,
        help="transcript width cap (default: 160; 0 for full width)",
    )
    return parser


def build_textual_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="view_trace_tui",
        description="Interactive textual trace viewer (a: toggle all, q: quit)",
    )
    parser.add_argument(
        "trace_file",
        nargs="?",
        default=None,
        help="path to trace file (or stdin if omitted)",
    )
    parser.add_argument(
        "--max-width",
        type=parse_max_width,
        default=160,
        help="transcript width cap (default: 160; 0 for full width)",
    )
    return parser


def enable_argcomplete(parser: argparse.ArgumentParser) -> None:
    import argcomplete

    argcomplete.autocomplete(parser)
