import unittest
from pathlib import Path

from rich import print as rich_print

from lsp.fs import *
from lsp.chunker import *
from lsp.chunks.ts import *
from lsp.storage import Chunk

# * set root dir for relative paths
repo_root = Path(__file__).parent.parent.parent.parent.parent
set_root_dir(repo_root)

# z rag
# ptw lsp/chunker_tests.py -- --capture=tee-sys

def _ts_chunks_from_file_with_fake_hash(path: Path, options: RAGChunkerOptions) -> list[Chunk]:
    return build_ts_chunks_from_source_bytes(path, "fake_hash", path.read_bytes(), options)

class TestReadingFilesAndNewLines(unittest.TestCase):
    """ purpose is to test that readlines is behaving the way I expect
        and that I carefully document newline behaviors (i.e. not stripping them)
    """

    def setUp(self):
        self.test_cases = Path(__file__).parent / ".." / "tests" / "test_cases"

    def test_readlines_final_line_not_empty_without_newline(self):
        test_file = self.test_cases / "readlines" / "final_line_not_empty_without_newline.txt"
        lines = read_text_lines(test_file)
        self.assertEqual(lines, ["1\n", "2\n", "3"])

        chunks = build_chunks_from_file(test_file, "fake_hash", RAGChunkerOptions.OnlyLineRangeChunks())
        first_chunk = chunks[0]
        self.assertEqual(first_chunk.text, "1\n2\n3")  # NO final \n

    def test_readlines_final_line_not_empty_with_newline(self):
        test_file = self.test_cases / "readlines" / "final_line_not_empty_with_newline.txt"
        lines = read_text_lines(test_file)
        self.assertEqual(lines, ["1\n", "2\n", "3\n"])

        chunks = build_chunks_from_file(test_file, "fake_hash", RAGChunkerOptions.OnlyLineRangeChunks())
        first_chunk = chunks[0]
        self.assertEqual(first_chunk.text, "1\n2\n3\n")

    def test_readlines_final_line_empty_with_newline(self):
        test_file = self.test_cases / "readlines" / "final_line_empty_with_newline.txt"
        lines = read_text_lines(test_file)
        self.assertEqual(lines, ["1\n", "2\n", "3\n", "\n"])

        chunks = build_chunks_from_file(test_file, "fake_hash", RAGChunkerOptions.OnlyLineRangeChunks())
        first_chunk = chunks[0]
        self.assertEqual(first_chunk.text, "1\n2\n3\n\n")

class TestLowLevel_LinesChunker(unittest.TestCase):
    """
    FYI this overlaps with tests in indexer_tests...
    - these tests are intended to be lower level to compliment indexer_tests
    """

    # TODO move some of the low level assertions out of indexer and into here by the way
    # ... i.e. intra chunk assertions should reside here

    def setUp(self):
        # create temp directory
        self.test_cases = Path(__file__).parent / ".." / "tests" / "test_cases"

    def test_build_line_range_chunks(self):
        lines = [str(x) + "\n" for x in range(0, 30)]  # 0\n1\n ... 29\n
        self.assertEqual(len(lines), 30)  # FYI mostly as reminder range is not inclusive :)
        chunks = build_line_range_chunks_from_lines(Path("foo.txt"), "fake_hash", lines)
        self.assertEqual(len(chunks), 2)
        chunk1 = chunks[0]
        expected_text1 = "0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n13\n14\n15\n16\n17\n18\n19\n"
        self.assertEqual(chunk1.text, expected_text1)
        self.assertEqual(chunk1.start_line0, 0)
        self.assertEqual(chunk1.end_line0, 19)
        self.assertEqual(chunk1.start_column0, 0)
        self.assertEqual(chunk1.end_column0, None)
        self.assertEqual(chunk1.file, "foo.txt")
        # chunk_id
        #   echo -n "foo.txt:lines:0-19:fake_hash" | sha256sum | cut -c -16
        self.assertEqual(chunk1.id, "fc78caf765f98c08")
        #   bitmaths "0xfc78caf765f98c08 & 0x7FFFFFFFFFFFFFFF"
        #      FYI this case id_int the high bits are truncated
        self.assertEqual(chunk1.id_int, "8969141821824928776")
        self.assertEqual(chunk1.type, "lines")
        self.assertEqual(chunk1.file_hash, "fake_hash")

        chunk2 = chunks[1]
        expected_text2 = "15\n16\n17\n18\n19\n20\n21\n22\n23\n24\n25\n26\n27\n28\n29\n"
        self.assertEqual(chunk2.text, expected_text2)
        self.assertEqual(chunk2.start_line0, 15)
        self.assertEqual(chunk2.end_line0, 29)  # 30 lines total, last has line 29 which is on file line 28
        self.assertEqual(chunk2.start_column0, 0)
        self.assertEqual(chunk2.end_column0, None)
        self.assertEqual(chunk2.file, "foo.txt")
        # chunk_id
        #   echo -n "foo.txt:lines:15-29:fake_hash" | sha256sum | cut -c -16
        self.assertEqual(chunk2.id, "5f0546bff37a52e6")
        #   bitmaths "0x5f0546bff37a52e6 & 0x7FFFFFFFFFFFFFFF"
        #     FYI no high_bits to truncate in this case
        self.assertEqual(chunk2.id_int, "6846956598724285158")
        self.assertEqual(chunk2.type, "lines")
        self.assertEqual(chunk2.file_hash, "fake_hash")

    def test_last_chunk_has_one_line_past_overlap__thus_is_kept(self):
        #   chunk1: 0=>19
        #   chunk2: 15=>20 # has one line past overlap, so keep chunk
        lines = [str(x) + "\n" for x in range(0, 21)]  # 0\n1\n ... 20\n
        self.assertEqual(len(lines), 21)
        chunks = build_line_range_chunks_from_lines(Path("foo.txt"), "fake_hash", lines)
        assert [(c.start_line0, c.end_line0) for c in chunks] == [(0, 19), (15, 20)]

    def test_last_chunk_would_only_be_overlap_so_it_is_skipped_due_to_min_chunk_size(self):
        # last chunk is only the 5 lines of overlap with first chunks, so its skipped
        #   chunk1: 0=>19
        #   chunk2: 15=>19 # skip as its only overlap
        lines = [str(x) + "\n" for x in range(0, 20)]  # 0\n1\n ... 19\n
        self.assertEqual(len(lines), 20)
        chunks = build_line_range_chunks_from_lines(Path("foo.txt"), "fake_hash", lines)
        assert [(c.start_line0, c.end_line0) for c in chunks] == [(0, 19)]

class TestTreesitterPythonChunker(unittest.TestCase):

    def setUp(self):
        self.test_cases = Path(__file__).parent / ".." / "tests" / "test_cases" / "ts"
        self.mydir = Path(__file__).parent

    def test_two_functions_py(self):
        chunks = _ts_chunks_from_file_with_fake_hash(self.test_cases / "two_functions.py", RAGChunkerOptions.OnlyTsChunks())
        self.assertEqual(len(chunks), 2)

        first_chunk = chunks[0]
        expected_func1_chunk_text = "def func1():\n    return 1"  # TODO new line between two funcs? how about skip that?
        self.assertEqual(first_chunk.text, expected_func1_chunk_text)

        second_chunk = chunks[1]
        expected_func2_chunk_text = "def func2():\n    return 2"
        self.assertEqual(second_chunk.text, expected_func2_chunk_text)

    def test_nested_functions_py(self):
        chunks = _ts_chunks_from_file_with_fake_hash(self.test_cases / "nested_functions.py", RAGChunkerOptions.OnlyTsChunks())
        self.assertEqual(len(chunks), 2)

        first_chunk = chunks[0]
        expected_first_chunk = "def f():\n\n    def g():\n        return 42"
        self.assertEqual(first_chunk.text, expected_first_chunk)

        second_chunk = chunks[1]
        expected_second_chunk = "def g():\n        return 42"
        self.assertEqual(second_chunk.text, expected_second_chunk)
        # TODO how do I want to handle nesting? maybe all in one if its under a token count?
        # and/or index nested too?

    def test_dataclass_py(self):
        chunks = _ts_chunks_from_file_with_fake_hash(self.test_cases / "dataclass.py", RAGChunkerOptions.OnlyTsChunks())
        self.assertEqual(len(chunks), 1)

        first_chunk = chunks[0]
        class_text = """class Customer():
    id: int
    name: str
    email: str"""
        self.assertEqual(first_chunk.text, class_text)

    def test_class_with_functions_py(self):
        chunks = _ts_chunks_from_file_with_fake_hash(self.test_cases / "class_with_functions.py", RAGChunkerOptions.OnlyTsChunks())

        self.assertEqual(len(chunks), 5)
        self.maxDiff = None

        first_chunk = chunks[0]
        class_text = """class Person():

    def __init__(self, first_name, last_name, dob):
        self.first_name = first_name
        self.last_name = last_name
        self.dob = dob

    def say_hi(self):
        return f'Hi, {self.first_name} {self.last_name}!'

    def is_of_age(self):
        current_year = datetime.now().year
        return (current_year - self.dob.year) >= 18

    def __str__(self):
        return f'Person({self.first_name}, {self.last_name}, {self.dob})'"""
        self.assertEqual(first_chunk.text, class_text)

        self.assertEqual(chunks[1].text, """def __init__(self, first_name, last_name, dob):
        self.first_name = first_name
        self.last_name = last_name
        self.dob = dob""")

        self.assertEqual(chunks[2].text, """def say_hi(self):
        return f'Hi, {self.first_name} {self.last_name}!'""")

        self.assertEqual(chunks[3].text, """def is_of_age(self):
        current_year = datetime.now().year
        return (current_year - self.dob.year) >= 18""")

        self.assertEqual(chunks[4].text, """def __str__(self):
        return f'Person({self.first_name}, {self.last_name}, {self.dob})'""")

    def WIP_test_ts_toplevel_query_py(self):
        from tree_sitter_languages import get_parser, get_language
        parser = get_parser("python")
        language = get_language("python")
        source_code = read_bytes(self.test_cases / "class_with_functions.py")

        tree = parser.parse(source_code)

        query_str = open(self.mydir / "chunker/queries/py/toplevel.scm").read()
        query = language.query(query_str)

        captures = query.captures(tree.root_node)
        for node, name in captures:
            print(name, node.type, node.start_point, node.end_point)

    def test_ts_toplevel_funcs_py(self):
        query_str = "(module (function_definition) @toplevel.func)"
        from tree_sitter_languages import get_parser, get_language
        parser = get_parser("python")
        language = get_language("python")
        file = self.test_cases / "two_functions.py"
        relpath = relative_to_workspace(file)

        source_code = read_bytes(file)

        tree = parser.parse(source_code)

        query = language.query(query_str)

        captures = query.captures(tree.root_node)
        print()  # blank line
        for node, name in captures:
            print(name, node.type, node.start_point, node.end_point)
            code_block = node.text.decode("utf-8")
            scope_path = func_name(node)
            sig_str = func_sig(node, source_code)

            rich_print(node.sexp())
            # BTW
            #  SIG: is two fold:
            #  - allows me to easily parse the key information about this chunk (i.e. if matched I can show that in UI)
            #    - without this you'd have to attempt to parse code again and that might not go well
            #  - PLUS it adds normalized context that the embeddings model can use
            #
            doc = f"""FILE: {relpath}
FUNC: {scope_path}
SIG : {sig_str}
CODE:
{code_block}
"""
            print(doc)

# DOC : {first_docline or ""}
