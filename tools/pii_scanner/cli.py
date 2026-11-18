"""Lightweight parser definition for pii_scanner."""

from __future__ import annotations

import argparse

from .constants import PII_CATEGORIES


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="pii_scanner",
        description="Scan JSON files for PII, or extract file paths from trace files.",
        epilog=f"PII categories: {', '.join(PII_CATEGORIES)}",
    )
    parser.add_argument(
        "target",
        nargs="?",
        default=".",
        help="Directory or single JSON file to scan (default: current directory)",
    )
    parser.add_argument(
        "--model",
        default=None,
        help=(
            "HuggingFace model name for transformers-based detection. "
            "If omitted, uses regex-based detection (no model download needed)."
        ),
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.5,
        help="Minimum confidence score to report a finding (default: 0.5)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output results as JSON to stdout",
    )
    parser.add_argument(
        "--show-matches",
        action="store_true",
        help="Display actual PII text instead of masked dots (use with caution)",
    )
    parser.add_argument(
        "--extract-paths",
        action="store_true",
        help="Extract file paths from *-trace.json files (skips PII scanning)",
    )
    return parser


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = build_parser()
    import argcomplete

    argcomplete.autocomplete(parser)
    return parser.parse_args(argv)
