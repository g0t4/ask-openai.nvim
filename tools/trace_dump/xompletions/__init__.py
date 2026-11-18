"""Native Xonsh completion for trace_dump."""


def xonsh_complete(ctx):
    from xonsh.cli_utils import ArgparseCompleter

    from ..cli import build_parser

    yield from ArgparseCompleter(build_parser(), command=ctx).complete()
