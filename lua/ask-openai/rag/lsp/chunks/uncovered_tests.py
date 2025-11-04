from pathlib import Path
from tree_sitter import Parser, Tree
from tree_sitter_language_pack import get_parser

from lsp.chunks.identified import IdentifiedChunk
from lsp.chunks.uncovered import _debug_uncovered_nodes
from lsp.logs import logging_fwk_to_console

logging_fwk_to_console("INFO")

class TestUncoveredNodes():

    def parse_lua(self, code: str) -> tuple[bytes, Tree]:
        parser = get_parser('lua')
        source_bytes = bytes(code, 'utf8')
        tree = parser.parse(source_bytes)
        return source_bytes, tree

    def test_fully_covered_single_function(self):
        source_bytes, tree = self.parse_lua('function a() return 1 end')
        identified_chunks = [IdentifiedChunk(
            sibling_nodes=[tree.root_node.children[0]],
            signature='a',
        )]
        print("tree", tree.root_node.children[0].start_byte, tree.root_node.children[0].end_byte)

        uncovered_code = _debug_uncovered_nodes(tree, source_bytes, identified_chunks)

        assert len(uncovered_code) == 0

    def test_single_function_uncovered(self):
        source_bytes, tree = self.parse_lua('function a() return 1 end')

        uncovered_code = _debug_uncovered_nodes(tree, source_bytes, [])

        assert len(uncovered_code) == 1
        only = uncovered_code[0]
        assert only.text == 'function a() return 1 end'
        assert only.start_line_base1 == 1
        assert only.end_line_base1 == 1

    def test_start_and_end_uncovered_code(self):
        # three functions, middle is covered
        code = 'function a() return 1 end\nfunction b() return 2 end\nfunction c() return 3 end'
        source_bytes, tree = self.parse_lua(code)
        identified_chunks = [IdentifiedChunk(
            sibling_nodes=[tree.root_node.children[1]],
            signature='b',
        )]

        # * review range inclusivity/exclusivity
        # print(f'{len(code)=}') # 77 characters (\n == 1 char)
        # print(len(source_bytes))  # 77 bytes
        #
        # print(f'{source_bytes[77]=}') # fails b/c no 78th char (this is base0)
        #
        # KEEP IN MIND \n => one byte (not two)
        #
        # for child in tree.root_node.children:
        #     # END BYTE IS NOT INCLUSIVE (checked total length is 77 on this example, last end_byte==77 Q.E.D.)
        #     print("child", child.start_byte, child.end_byte, str(child.text))
        #     print(f'{child.byte_range=} {child.range=}')
        # child.byte_range=(0, 25) child.range=<Range start_point=(0, 0), end_point=(0, 25), start_byte=0, end_byte=25>
        #   a => (0,25]  or (0,24) -- 25 chars
        # char #25 (base0) is SKIPPED (\n) - treesitter skips this (see consecutive end/start_byte values and it's missing
        # child.byte_range=(26, 51) child.range=<Range start_point=(1, 0), end_point=(1, 25), start_byte=26, end_byte=51>
        #   b => (26,51] or (26,50) -- \n==1 + 25 chars == 26 chars
        # char #51 (base0) is SKIPPED (\n)
        # child.byte_range=(52, 77) child.range=<Range start_point=(2, 0), end_point=(2, 25), start_byte=52, end_byte=77>       #
        #   c => (52,77] or (52,76) -- 26 chars too (same \n==1 + 25 chars)
        #   ends are OPEN/CLOSE (confirmed)

        uncovered_code = _debug_uncovered_nodes(tree, source_bytes, identified_chunks)

        assert len(uncovered_code) == 2
        start_uncovered = uncovered_code[0]
        assert start_uncovered.text == 'function a() return 1 end\n'
        assert start_uncovered.start_line_base1 == 1
        assert start_uncovered.end_line_base1 == 2
        end_uncovered = uncovered_code[1]
        # TODO look into how whitespace is handled (here it's tacking onto start of 3rd function which is fine)
        #   I just need to understand how it works so I am not surprised
        #   mostly shouldn't matter aside from writing tests
        # TODO review leading \n
        assert end_uncovered.text == '\nfunction c() return 3 end'
        assert end_uncovered.start_line_base1 == 2
        assert end_uncovered.end_line_base1 == 3

    def test_middle_uncovered_code(self):
        source_bytes, tree = self.parse_lua('function a() return 1 end\nfunction b() return 2 end\nfunction c() return 3 end')
        identified_chunks = [IdentifiedChunk(
            sibling_nodes=[tree.root_node.children[0]],
            signature='a',
        ), IdentifiedChunk(
            sibling_nodes=[tree.root_node.children[2]],
            signature='c',
        )]

        uncovered_code = _debug_uncovered_nodes(tree, source_bytes, identified_chunks)

        assert len(uncovered_code) == 1
        middle_uncovered = uncovered_code[0]
        # TODO review leading \n
        # TODO review how I feel about \n bumping up ending_line_base1? what impact?
        assert middle_uncovered.text == '\nfunction b() return 2 end\n'
        assert middle_uncovered.start_line_base1 == 1
        assert middle_uncovered.end_line_base1 == 3

    def test_consecutive_covered_code_in_single_chunk(self):
        # FYI right now this will apply to decorators/annotations/doc_comments in python/lua (more in future)
        source_bytes, tree = self.parse_lua('--- doc comment\nfunction a() return 1 end')
        identified_chunks = [
            IdentifiedChunk(
                sibling_nodes=[
                    # TWO in ONE chunk (why? b/c then the non-covered whitespace in between should be covered)
                    tree.root_node.children[0],
                    tree.root_node.children[1],
                ],
                signature="consecutive_single_chunk",
            ),
        ]

        uncovered_code = _debug_uncovered_nodes(tree, source_bytes, identified_chunks)

        # newline between is not covered, that's fine to track, I can always ignore it in consumers
        assert len(uncovered_code) == 0

    def test_consecutive_covered_code(self):
        # it is possible I don't need this test
        source_bytes, tree = self.parse_lua('function a() return 1 end\nfunction b() return 2 end')
        identified_chunks = [IdentifiedChunk(
            sibling_nodes=[tree.root_node.children[0]],
            signature='a',
        ), IdentifiedChunk(
            sibling_nodes=[tree.root_node.children[1]],
            signature='b',
        )]

        uncovered_code = _debug_uncovered_nodes(tree, source_bytes, identified_chunks)

        # newline between is not covered, that's fine to track, I can always ignore it in consumers
        assert len(uncovered_code) == 1
        only = uncovered_code[0]
        assert only.text == '\n'
        assert only.start_line_base1 == 1
        assert only.end_line_base1 == 2

    def test_non_consecutive_single_chunk(self):
        # I do not have plans for this currently, nonetheless it can help me sniff out edge cases in my uncovered detection
        source_bytes, tree = self.parse_lua('function a() return 1 end\nfunction b() return 2 end\nfunction c() return 3 end')
        func_a = tree.root_node.children[0]
        func_c = tree.root_node.children[2]
        identified_chunks = [
            IdentifiedChunk(
                # hypothetically could chunk non-contiguous nodes
                sibling_nodes=[func_a, func_c],
                signature='a',
            )
        ]

        uncovered_code = _debug_uncovered_nodes(tree, source_bytes, identified_chunks)

        assert len(uncovered_code) == 1
        only = uncovered_code[0]
        # TODO review leading \n
        assert only.text == '\nfunction b() return 2 end\n'
        assert only.start_line_base1 == 1
        assert only.end_line_base1 == 3

    def test_overlapping_nodes_within_single_chunk_with_uncovered_after(self):
        # THIS is not a real use case currently, though it should work fine to keep this test
        #   right now I would only be merging TOP level consecutive nodes (overlapping end up as separate identified_chunks)
        source_bytes, tree = self.parse_lua('function a() function a_nested() return 1 end end\nfunction b() return 2 end')
        func_a = tree.root_node.children[0]
        func_a_nested = func_a.named_children[0]
        # func_b = tree.root_node.children[1]
        identified_chunks = [
            IdentifiedChunk(
                # hypothetically could chunk non-contiguous nodes
                sibling_nodes=[func_a, func_a_nested],
                signature='a',
            ),
        ]

        uncovered_code = _debug_uncovered_nodes(tree, source_bytes, identified_chunks)
        assert len(uncovered_code) == 1
        only = uncovered_code[0]
        # TODO review leading \n
        assert only.text == '\nfunction b() return 2 end'
        assert only.start_line_base1 == 1
        assert only.end_line_base1 == 2

    def test_overlapping_nodes_in_separate_chunks_with_uncovered_after(self):
        # this touches on merged_covered_spans
        source_bytes, tree = self.parse_lua('function a() function a_nested() return 1 end end\nfunction b() return 2 end')
        func_a = tree.root_node.children[0]
        func_a_nested = func_a.named_children[0]
        func_b = tree.root_node.children[1]
        identified_chunks = [
            IdentifiedChunk(
                # hypothetically could chunk non-contiguous nodes
                sibling_nodes=[func_a],
                signature='a',
            ),
            IdentifiedChunk(
                sibling_nodes=[func_a_nested],
                signature='a_nested',
            ),
        ]
        uncovered_code = _debug_uncovered_nodes(tree, source_bytes, identified_chunks)
        assert len(uncovered_code) == 1
        only = uncovered_code[0]
        # TODO review leading \n
        assert only.text == '\nfunction b() return 2 end'
        assert only.start_line_base1 == 1
        assert only.end_line_base1 == 2
