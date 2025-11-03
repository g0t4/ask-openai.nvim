from pathlib import Path
from tree_sitter_language_pack import get_parser

from lsp.chunks.uncovered import _debug_uncovered_nodes
from lsp.logs import logging_fwk_to_console

logging_fwk_to_console("INFO")

class TestUncoveredNodes():

    def test_single_function_uncovered(self):
        lua_parser = get_parser('lua')
        source_bytes = bytes('function a() return 1 end', 'utf8')
        tree = lua_parser.parse(source_bytes)
        uncovered_code = _debug_uncovered_nodes(tree, source_bytes, [], Path('foo.lua'))
        assert len(uncovered_code) == 1
        only = uncovered_code[0]
        assert only.text == 'function a() return 1 end'
        assert only.start_line_base1 == 1
        assert only.end_line_base1 == 1

    # TODO flesh out tests of returning the uncovered code
