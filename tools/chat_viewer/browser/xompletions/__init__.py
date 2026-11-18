"""Native Xonsh completion for browse_traces."""

COMMAND = "browse_traces"


def xonsh_complete(ctx):
    from xonsh.cli_utils import ArgparseCompleter

    from ..cli import build_parser

    yield from ArgparseCompleter(build_parser(), command=ctx).complete()
