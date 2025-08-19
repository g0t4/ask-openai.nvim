import unittest
from pathlib import Path

from rich import print as rich_print

from lsp.fs import *
from lsp.chunker import build_line_range_chunks_from_lines, build_chunks_from_file, build_ts_chunks_from_file
from lsp.chunks.ts import *

# * set root dir for relative paths
repo_root = Path(__file__).parent.parent.parent.parent.parent
set_root_dir(repo_root)

# z rag
# ptw lsp/chunker_tests.py -- --capture=tee-sys

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

        chunks = build_chunks_from_file(test_file, "fake_hash", enable_line_range_chunks=True, enable_ts_chunks=False)
        first_chunk = chunks[0]
        self.assertEqual(first_chunk.text, "1\n2\n3")  # NO final \n

    def test_readlines_final_line_not_empty_with_newline(self):
        test_file = self.test_cases / "readlines" / "final_line_not_empty_with_newline.txt"
        lines = read_text_lines(test_file)
        self.assertEqual(lines, ["1\n", "2\n", "3\n"])

        chunks = build_chunks_from_file(test_file, "fake_hash", enable_line_range_chunks=True, enable_ts_chunks=False)
        first_chunk = chunks[0]
        self.assertEqual(first_chunk.text, "1\n2\n3\n")

    def test_readlines_final_line_empty_with_newline(self):
        test_file = self.test_cases / "readlines" / "final_line_empty_with_newline.txt"
        lines = read_text_lines(test_file)
        self.assertEqual(lines, ["1\n", "2\n", "3\n", "\n"])

        chunks = build_chunks_from_file(test_file, "fake_hash", enable_line_range_chunks=True, enable_ts_chunks=False)
        first_chunk = chunks[0]
        self.assertEqual(first_chunk.text, "1\n2\n3\n\n")

class TestLinesChunker(unittest.TestCase):

    def setUp(self):
        # create temp directory
        self.test_cases = Path(__file__).parent / ".." / "tests" / "test_cases"

    def test_build_file_chunks_has_new_lines_on_end_of_lines(self):
        # largely to document how I am using readlines + build_from_lines
        chunks = build_chunks_from_file(self.test_cases / "numbers.30.txt", "fake_hash", enable_line_range_chunks=True, enable_ts_chunks=False)
        self.assertEqual(len(chunks), 2)
        first_chunk = chunks[0]
        expected_first_chunk_text = "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n13\n14\n15\n16\n17\n18\n19\n20\n"
        self.assertEqual(first_chunk.text, expected_first_chunk_text)

    def test_build_line_range_chunks(self):
        # FYI this test overlaps with integration tests in indexer_tests.py
        #  but I want these documented because I will add other chunking strategies into build[er].py
        lines = ["line " + str(x) + "\n" for x in range(1, 30)]
        chunks = build_line_range_chunks_from_lines(Path("foo.txt"), "fake_hash", lines)
        self.assertEqual(len(chunks), 2)
        first_chunk = chunks[0]
        expected_first_chunk_text = "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\n"
        self.assertEqual(first_chunk.text, expected_first_chunk_text)

        second_chunk = chunks[1]
        expected_second_chunk_text = "line 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\n"
        self.assertEqual(second_chunk.text, expected_second_chunk_text)

class TestTreesitterPythonChunker(unittest.TestCase):

    def setUp(self):
        self.test_cases = Path(__file__).parent / ".." / "tests" / "test_cases" / "ts"
        self.mydir = Path(__file__).parent

    def test_two_functions_py(self):
        chunks = build_ts_chunks_from_file(self.test_cases / "two_functions.py", "fake_hash")
        self.assertEqual(len(chunks), 2)

        first_chunk = chunks[0]
        expected_func1_chunk_text = "def func1():\n    return 1"  # TODO new line between two funcs? how about skip that?
        self.assertEqual(first_chunk.text, expected_func1_chunk_text)

        second_chunk = chunks[1]
        expected_func2_chunk_text = "def func2():\n    return 2"
        self.assertEqual(second_chunk.text, expected_func2_chunk_text)

    def test_nested_functions_py(self):
        chunks = build_ts_chunks_from_file(self.test_cases / "nested_functions.py", "fake_hash")
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
        chunks = build_ts_chunks_from_file(self.test_cases / "dataclass.py", "fake_hash")
        self.assertEqual(len(chunks), 1)

        first_chunk = chunks[0]
        class_text = """class Customer():
    id: int
    name: str
    email: str"""
        self.assertEqual(first_chunk.text, class_text)

    def test_class_with_functions_py(self):
        chunks = build_ts_chunks_from_file(self.test_cases / "class_with_functions.py", "fake_hash")
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
