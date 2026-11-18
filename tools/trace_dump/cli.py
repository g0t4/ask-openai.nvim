"""Lightweight parser definition for trace_dump."""

from __future__ import annotations

import argparse


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="trace_dump",
        description="Dump commands from a trace file.",
    )
    parser.add_argument(
        "trace_file",
        help="Path to the -trace.json file to analyze.",
    )
    parser.add_argument(
        "--plain-text",
        action="store_true",
        default=False,
        help="Output plain text without colors or panel borders.",
    )
    return parser


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = build_parser()
    import argcomplete

    argcomplete.autocomplete(parser)
    return parser.parse_args(argv)
