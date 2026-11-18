"""Native Xonsh completion for pii_scanner."""


def xonsh_complete(ctx):
    from xonsh.cli_utils import ArgparseCompleter

    from ..cli import build_parser

    yield from ArgparseCompleter(build_parser(), command=ctx).complete()
