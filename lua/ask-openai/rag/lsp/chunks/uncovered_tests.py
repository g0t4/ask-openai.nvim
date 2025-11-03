from pathlib import Path
from tree_sitter_language_pack import get_parser

from lsp.chunks.uncovered import _debug_uncovered_nodes
from lsp.logs import logging_fwk_to_console

logging_fwk_to_console("INFO")

class TestUncoveredNodes():

    def test_uncovered(self):
        lua_parser = get_parser('lua')
        tree = lua_parser.parse(bytes('function a() return 1 end', 'utf8'))
        _debug_uncovered_nodes(tree, bytes('function a() return 1 end', 'utf8'), [], Path('foo.lua'))
        assert 1 == 1

    # TODO flesh out tests of returning the uncovered code
