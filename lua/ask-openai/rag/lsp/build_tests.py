from pathlib import Path

import json
import logging
import unittest

from lsp.build import build_from_lines, build_file_chunks
from lsp.logs import logging_fwk_to_console

logging_fwk_to_console(logging.DEBUG)

# z rag
# ptw lsp/build_tests.py -- --capture=tee-sys

class TestChunkBuilding(unittest.TestCase):

    def setUp(self):
        # create temp directory
        self.test_cases = Path(__file__).parent / ".." / "tests" / "test_cases"

    def test_build_file_chunks_has_new_lines_on_end_of_lines(self):
        # largely to document how I am using readlines + build_from_lines
        numbers30 = self.test_cases / "numbers.30.txt"
        chunks = build_file_chunks(numbers30, "fake_hash")
        self.assertEqual(len(chunks), 2)
        first_chunk = chunks[0]
        expected_first_chunk_text = "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n13\n14\n15\n16\n17\n18\n19\n20"
        self.assertEqual(first_chunk.text, expected_first_chunk_text)

    def test_build_line_range_chunks(self):
        # FYI this test overlaps with integration tests in indexer_tests.py
        #  but I want these documented because I will add other chunking strategies into build[er].py
        lines = ["line " + str(x) + "\n" for x in range(1, 30)]
        chunks = build_from_lines(Path("foo.txt"), "fake_hash", lines)
        self.assertEqual(len(chunks), 2)
        first_chunk = chunks[0]
        expected_first_chunk_text = "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20"
        self.assertEqual(first_chunk.text, expected_first_chunk_text)

        # self.assertEqual(first_chunk
        # second_chunk = chunks[1]
