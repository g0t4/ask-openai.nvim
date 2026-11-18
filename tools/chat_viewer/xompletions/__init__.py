"""Native Xonsh completion for the chat viewer commands."""

import os


COMMANDS = ("view_trace", "view_trace_tui")


def xonsh_complete(ctx):
    from xonsh.cli_utils import ArgparseCompleter

    from ..cli import build_parser, build_textual_parser

    command = os.path.basename(ctx.command)
    parser = build_textual_parser() if command == "view_trace_tui" else build_parser()
    yield from ArgparseCompleter(parser, command=ctx).complete()
