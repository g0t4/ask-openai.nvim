from pathlib import Path
from tree_sitter_language_pack import get_parser

from lsp.chunks.identified import IdentifiedChunk
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

    def test_start_and_end_uncovered_code(self):
        # three functions, middle is covered
        lua_parser = get_parser('lua')
        source_bytes = bytes('function a() return 1 end\nfunction b() return 2 end\nfunction c() return 3 end', 'utf8')
        tree = lua_parser.parse(source_bytes)
        identified_chunks = [IdentifiedChunk(
            sibling_nodes=[tree.root_node.children[1]],
            signature='function b() return 2 end',
        )]
        uncovered_code = _debug_uncovered_nodes(tree, source_bytes, identified_chunks, Path('foo.lua'))
        assert len(uncovered_code) == 2
        start_uncovered = uncovered_code[0]
        assert start_uncovered.text == 'function a() return 1 end'
        assert start_uncovered.start_line_base1 == 1
        assert start_uncovered.end_line_base1 == 1
        end_uncovered = uncovered_code[1]
        # TODO look into how whitespace is handled (here it's tacking onto start of 3rd function which is fine)
        #   I just need to understand how it works so I am not surprised
        #   mostly shouldn't matter aside from writing tests
        assert end_uncovered.text == '\nfunction c() return 3 end'
        assert end_uncovered.start_line_base1 == 2
        assert end_uncovered.end_line_base1 == 3

    # TODO flesh out tests of returning the uncovered code
