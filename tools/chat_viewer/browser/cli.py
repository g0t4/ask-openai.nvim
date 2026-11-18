"""Lightweight parser definition for the trace browser."""

import argparse


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="browse_traces", description="Trace browser REPL"
    )
    parser.add_argument(
        "from_dir",
        nargs="?",
        default="",
        help="path or from_dir: fim, rewrite, agents",
    )
    return parser


def enable_argcomplete(parser: argparse.ArgumentParser) -> None:
    import argcomplete

    argcomplete.autocomplete(parser)
