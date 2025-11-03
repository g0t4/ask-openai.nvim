from pathlib import Path

from rich import print as rich_print
from tree_sitter import QueryCursor

from lsp.fs import *
from lsp.chunks.chunker import *
from lsp.chunks.ts import *
from lsp.storage import Chunk

# * set root dir for relative paths
repo_root = Path(__file__).parent.parent.parent.parent.parent.parent
my_dir = Path(__file__).parent.parent
test_cases = my_dir / "../tests/test_cases"
test_cases_treesitter = my_dir / "../tests/test_cases/treesitter"
test_cases_python = test_cases_treesitter / "python"
test_cases_typescript = test_cases_treesitter / "typescript"
test_cases_c = test_cases_treesitter / "c"
test_cases_cpp = test_cases_treesitter / "cpp"
test_cases_csharp = test_cases_treesitter / "csharp"
test_cases_rust = test_cases_treesitter / "rust"
test_cases_lua = test_cases_treesitter / "lua"

set_root_dir(repo_root)

# z rag
# ptw lsp/chunker_tests.py -- --capture=tee-sys

def build_test_chunks(path: Path, options: RAGChunkerOptions) -> list[Chunk]:
    return build_ts_chunks_from_source_bytes(path, "fake_hash", path.read_bytes(), options)

class TestReadingFilesAndNewLines:
    """ purpose is to test that readlines is behaving the way I expect
        and that I carefully document newline behaviors (i.e. not stripping them)
    """

    def test_readlines_final_line_not_empty_without_newline(self):
        test_file = test_cases / "readlines" / "final_line_not_empty_without_newline.txt"
        lines = read_text_lines(test_file)
        assert lines == ["1\n", "2\n", "3"]

        chunks = build_chunks_from_file(test_file, "fake_hash", RAGChunkerOptions.OnlyLineRangeChunks())
        first_chunk = chunks[0]
        assert first_chunk.text == "1\n2\n3"  # NO final \n

    def test_readlines_final_line_not_empty_with_newline(self):
        test_file = test_cases / "readlines" / "final_line_not_empty_with_newline.txt"
        lines = read_text_lines(test_file)
        assert lines == ["1\n", "2\n", "3\n"]

        chunks = build_chunks_from_file(test_file, "fake_hash", RAGChunkerOptions.OnlyLineRangeChunks())
        first_chunk = chunks[0]
        assert first_chunk.text == "1\n2\n3\n"

    def test_readlines_final_line_empty_with_newline(self):
        test_file = test_cases / "readlines" / "final_line_empty_with_newline.txt"
        lines = read_text_lines(test_file)
        assert lines == ["1\n", "2\n", "3\n", "\n"]

        chunks = build_chunks_from_file(test_file, "fake_hash", RAGChunkerOptions.OnlyLineRangeChunks())
        first_chunk = chunks[0]
        assert first_chunk.text == "1\n2\n3\n\n"

class TestLowLevel_LinesChunker:
    """
    FYI this overlaps with tests in indexer_tests...
    - these tests are intended to be lower level to compliment indexer_tests
    """

    # TODO move some of the low level assertions out of indexer and into here by the way
    # ... i.e. intra chunk assertions should reside here

    def test_build_line_range_chunks(self):
        lines = [str(x) + "\n" for x in range(0, 30)]  # 0\n1\n ... 29\n
        assert len(lines) == 30  # FYI mostly as reminder range is not inclusive :)
        chunks = build_line_range_chunks_from_lines(Path("foo.txt"), "fake_hash", lines)
        assert len(chunks) == 2
        chunk1 = chunks[0]
        expected_text1 = "0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n13\n14\n15\n16\n17\n18\n19\n"
        assert chunk1.text == expected_text1
        assert chunk1.start_line0 == 0
        assert chunk1.end_line0 == 19
        assert chunk1.start_column0 == 0
        assert chunk1.end_column0 == None
        assert chunk1.file == "foo.txt"
        # chunk_id
        #   echo -n "foo.txt:lines:0-19:fake_hash" | sha256sum | cut -c -16
        assert chunk1.id == "fc78caf765f98c08"
        #   bitmaths "0xfc78caf765f98c08 & 0x7FFFFFFFFFFFFFFF"
        #      FYI this case id_int the high bits are truncated
        assert chunk1.id_int == "8969141821824928776"
        assert chunk1.type == "lines"
        assert chunk1.file_hash == "fake_hash"

        chunk2 = chunks[1]
        expected_text2 = "15\n16\n17\n18\n19\n20\n21\n22\n23\n24\n25\n26\n27\n28\n29\n"
        assert chunk2.text == expected_text2
        assert chunk2.start_line0 == 15
        assert chunk2.end_line0 == 29  # 30 lines total, last has line 29 which is on file line 28
        assert chunk2.start_column0 == 0
        assert chunk2.end_column0 == None
        assert chunk2.file == "foo.txt"
        # chunk_id
        #   echo -n "foo.txt:lines:15-29:fake_hash" | sha256sum | cut -c -16
        assert chunk2.id == "5f0546bff37a52e6"
        #   bitmaths "0x5f0546bff37a52e6 & 0x7FFFFFFFFFFFFFFF"
        #     FYI no high_bits to truncate in this case
        assert chunk2.id_int == "6846956598724285158"
        assert chunk2.type == "lines"
        assert chunk2.file_hash == "fake_hash"

    def test_last_chunk_has_one_line_past_overlap__thus_is_kept(self):
        #   chunk1: 0=>19
        #   chunk2: 15=>20 # has one line past overlap, so keep chunk
        lines = [str(x) + "\n" for x in range(0, 21)]  # 0\n1\n ... 20\n
        assert len(lines) == 21
        chunks = build_line_range_chunks_from_lines(Path("foo.txt"), "fake_hash", lines)
        assert [(c.start_line0, c.end_line0) for c in chunks] == [(0, 19), (15, 20)]

    def test_last_chunk_would_only_be_overlap_so_it_is_skipped_due_to_min_chunk_size(self):
        # last chunk is only the 5 lines of overlap with first chunks, so its skipped
        #   chunk1: 0=>19
        #   chunk2: 15=>19 # skip as its only overlap
        lines = [str(x) + "\n" for x in range(0, 20)]  # 0\n1\n ... 19\n
        assert len(lines) == 20
        chunks = build_line_range_chunks_from_lines(Path("foo.txt"), "fake_hash", lines)
        assert [(c.start_line0, c.end_line0) for c in chunks] == [(0, 19)]

class TestTreesitterChunker_Python_TopLevelFunctions:

    def setup_method(self):
        # node.type='function_definition'
        #   child.type='def'
        #     text='def'
        #   child.type='identifier'
        #     text='func1'
        #   child.type='parameters'
        #     text='()'
        #   child.type=':'
        #     text=':'
        #   child.type='block'
        #     text='return 1'
        chunks = build_test_chunks(test_cases_python / "two_functions.py", RAGChunkerOptions.OnlyTsChunks())
        assert len(chunks) == 2
        self.first_chunk = chunks[0]
        self.second_chunk = chunks[1]

    def test_two_top_level_functions(self):
        assert self.first_chunk.text == "def func1():\n    return 1"
        assert self.second_chunk.text == "def func2():\n    return 2"

    def test_example_treesitter_query(self):
        query_str = "(module (function_definition) @toplevel.func)"
        from tree_sitter_language_pack import get_parser, get_language
        parser = get_parser("python")
        language = get_language("python")
        file = test_cases_python / "two_functions.py"
        relpath = relative_to_workspace(file)

        source_code = read_bytes(file)

        tree = parser.parse(source_code)

        query = language.query(query_str)
        query_cursor = QueryCursor(query)

        def node_sexp(node, depth=0):
            # simulate node.sexp() which is no longer present in latest py-tree-sitter
            #  removed here: https://github.com/tree-sitter/py-tree-sitter/pull/208
            children = [node_sexp(child, depth + 1) for child in node.children]
            inner = " ".join(children)
            return f"({node.type} {inner})" if inner else f"({node.type})"

        captures = query_cursor.captures(tree.root_node)
        print()  # blank line
        for name, nodes in captures.items():
            for node in nodes:
                print(f"{name=}, {node.type=}, {node.start_point=}, {node.end_point=}")
                code_block = node.text.decode("utf-8")
                scope_path = func_name(node)
                sig_str = func_sig(node, source_code)

                rich_print("sexp", node_sexp(node))
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

class TestTreesitterChunker_Python_Decorators:

    def TODO_test_functions_with_decorators(self):
        chunks = build_test_chunks(test_cases_python / "decorators.py", RAGChunkerOptions.OnlyTsChunks())
        # TODO

    def TODO_test_decorated_class(self):
        chunks = build_test_chunks(test_cases_python / "decorators.py", RAGChunkerOptions.OnlyTsChunks())
        # TODO

    def TODO_test_nested_function_with_decorator(self):
        chunks = build_test_chunks(test_cases_python / "decorators.py", RAGChunkerOptions.OnlyTsChunks())
        #  log_and_call_nested => functools.lru_cache()
        # TODO

class TestTreesitterChunker_Lua_DocumentationComments:
    # BTW DocComments / DocumentationComments refers to BOTH:
    # - annotations
    # - regular comments
    # BOTH must immediately precede the member (i.e. function, table) w/o blank line(s)

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_lua / "doc_comments.lua", RAGChunkerOptions.OnlyTsChunks())

    def test_function_annotations_Adder(self):
        chunk = self.chunks[0]
        assert chunk.text == """---@param a number
---@param b number
---@return number
function Adder(a, b)
    return a + b
end"""

    def test_function_with_non_annotation_doc_comment(self):
        chunk = self.chunks[1]
        assert chunk.text == """--- Vector3 constructor
---@param x number
---@param y number
---@param z number
---@return Vector3
function Vector3.new(x, y, z)
    local t = { x = x, y = y, z = z }
    setmetatable(t, Vector3)
    return t
end"""

    def test_function_without_blank_line_before_comments(self):
        chunk = self.chunks[2]
        # in this case, the comments are right after a prior function defintion
        assert chunk.text == """--- example of no blank line before function comments
---@param a Vector3
---@param b Vector3
---@return Vector3
function Vector3.__add(a, b)
    return Vector3.new(a.x + b.x, a.y + b.y, a.z + b.z)
end"""

    def TODO_test_table_annotations(self):
        # TODO update indicies of function chunks above (or more table chunk after them)
        chunk = self.chunks[1]
        # TODO support top level tables? OR not? should this just be part of sliding window coverage?
#         assert chunk.text == """---@class Vector3
# ---@field x number
# ---@field y number
# ---@field z number
# local Vector3 = {}"""

    def test_function_with_preceding_unrelated_comment(self):
        chunk = self.chunks[3]
        # TODO FINISH unrelated comments
#         assert chunk.text == """function Subtract(a, b)
#     return a - b
# end
# """

    def test_function_with_preceding_unrelated_comment_before_annotation_comments(self):
        chunk = self.chunks[4]
        # TODO FINISH unrelated comments

#         assert chunk.text == """---@return number
# function Multiply(a, b)
#     return a * b
# end
# """

class TestTreesitterChunker_Python_NestedFunctions:

    def test_nested_functions(self):
        chunks = build_test_chunks(test_cases_python / "nested_functions.py", RAGChunkerOptions.OnlyTsChunks())
        assert len(chunks) == 2

        first_chunk = chunks[0]
        expected_first_chunk = "def f():\n\n    def g():\n        return 42"
        assert first_chunk.text == expected_first_chunk

        second_chunk = chunks[1]
        expected_second_chunk = "def g():\n        return 42"
        assert second_chunk.text == expected_second_chunk
        # TODO how do I want to handle nesting? maybe all in one if its under a token count?
        # and/or index nested too?

class TestTreesitterChunker_Python_DataClass:

    def test_dataclass(self):
        chunks = build_test_chunks(test_cases_python / "dataclass.py", RAGChunkerOptions.OnlyTsChunks())
        assert len(chunks) == 1

        first_chunk = chunks[0]
        class_text = """class Customer():
    id: int
    name: str
    email: str"""
        assert first_chunk.text == class_text

        assert first_chunk.signature == "class Customer():"

class TestTreesitterChunker_Python_Class:

    def setup_method(self):
        self.test_file = test_cases_python / "class_with_functions.py"
        self.chunks = build_test_chunks(self.test_file, RAGChunkerOptions.OnlyTsChunks())

    def test_class_has_correct_code(self):
        chunks = self.chunks

        assert len(chunks) == 5
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
        assert first_chunk.text == class_text

    def test_each_method_is_chunked(self):
        chunks = self.chunks

        assert chunks[1].text == """def __init__(self, first_name, last_name, dob):
        self.first_name = first_name
        self.last_name = last_name
        self.dob = dob"""

        assert chunks[2].text == """def say_hi(self):
        return f'Hi, {self.first_name} {self.last_name}!'"""

        assert chunks[3].text == """def is_of_age(self):
        current_year = datetime.now().year
        return (current_year - self.dob.year) >= 18"""

        assert chunks[4].text == """def __str__(self):
        return f'Person({self.first_name}, {self.last_name}, {self.dob})'"""

    def test_signatures(self):
        chunks = build_test_chunks(test_cases_python / "class_with_functions.py", RAGChunkerOptions.OnlyTsChunks())
        first_chunk = chunks[0]

        assert first_chunk.signature == "class Person():"

        assert chunks[1].signature == "def __init__(self, first_name, last_name, dob):"
        assert chunks[2].signature == "def say_hi(self):"
        assert chunks[3].signature == "def is_of_age(self):"
        assert chunks[4].signature == "def __str__(self):"

    # def WIP_test_ts_toplevel_query_py(self):
    #     from tree_sitter_language_pack import get_parser, get_language
    #     parser = get_parser("python")
    #     language = get_language("python")
    #     source_code = read_bytes(test_cases_python / "class_with_functions.py")
    #
    #     tree = parser.parse(source_code)
    #
    #     query_str = open(TODO / "chunker/queries/py/toplevel.scm").read()
    #     query = language.query(query_str)
    #
    #     captures = query.captures(tree.root_node)
    #     for node, name in captures:
    #         print(name, node.type, node.start_point, node.end_point)

class TestTreesitterChunker_Typescript_TopLevelFunctions:

    # * only this test class:
    #    trigger on any changes to chunker____ files (not just test code)
    # ptw lsp/chunks/chunker* -- --capture=tee-sys -k TestTreesitterTypescriptChunker
    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_typescript / "calc.ts", RAGChunkerOptions.OnlyTsChunks())

    def test_code(self):
        chunks = self.chunks

        assert len(chunks) >= 4

        add_chunk = chunks[0]
        expected_func1_chunk_text = "function add(a: number, b: number): number {\n    return a + b;\n}"
        assert add_chunk.text == expected_func1_chunk_text

        sub_chunk = chunks[1]
        expected_func2_chunk_text = "function subtract(a: number, b: number): number {\n    return a - b;\n}"
        assert sub_chunk.text == expected_func2_chunk_text

        mul_chunk = chunks[2]
        expected_func3_chunk_text = "function multiply(a: number, b: number): number {\n    return a * b;\n}"
        assert mul_chunk.text == expected_func3_chunk_text

        div_chunk = chunks[3]
        expected_func4_chunk_text = "function divide(a: number, b: number): number {\n    return a / b;\n}"
        assert div_chunk.text == expected_func4_chunk_text

    def test_signatures(self):
        #
        # * BTW, structure in typescript (top level func):
        # function_declaration node:
        #     child.type='function'
        #       text='function'
        #     child.type='identifier'
        #       text='add'
        #     child.type='formal_parameters'
        #       text='(a: number, b: number)'
        #     child.type='type_annotation'
        #       text=': number'
        #     child.type='statement_block'
        #       text='{\n    return a + b;\n}'
        #       * thus we want to stop before statement_block, thant results in the signature!
        #       * do not want body in the signature!
        #       * works the same as function_definition in python

        chunks = self.chunks

        add_chunk = chunks[0]
        assert add_chunk.signature == "function add(a: number, b: number): number"

        sub_chunk = chunks[1]
        assert sub_chunk.signature == "function subtract(a: number, b: number): number"

        mul_chunk = chunks[2]
        assert mul_chunk.signature == "function multiply(a: number, b: number): number"

        div_chunk = chunks[3]
        assert div_chunk.signature == "function divide(a: number, b: number): number"

class TestTreesitterChunker_Typescript_Class:

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_typescript / "calc.ts", RAGChunkerOptions.OnlyTsChunks())

    def test_code(self):
        chunks = self.chunks
        assert len(chunks) >= 5

        class_chunk = chunks[4]
        expected_class_text = "class Calculator {\n    add(a: number, b: number): number {\n        return add(a, b);\n    }\n    subtract(a: number, b: number): number {\n        return subtract(a, b);\n    }\n    multiply(a: number, b: number): number {\n        return multiply(a, b);\n    }\n    divide(a: number, b: number): number {\n        return divide(a, b);\n    }\n}"

        assert class_chunk.text == expected_class_text

    def test_signature(self):
        chunks = self.chunks

        class_chunk = chunks[4]

        assert class_chunk.signature == "class Calculator"

class TestTreesitterChunker_c_Functions:

    def setup_method(self):
        chunks = build_test_chunks(test_cases_c / "hello.c", RAGChunkerOptions.OnlyTsChunks())
        assert len(chunks) == 1
        self.main_chunk = chunks[0]

    def test_code(self):
        expected_main_text = "int main() {\n    printf(\"Hello, World!\\n\");"
        assert self.main_chunk.text.startswith(expected_main_text) == True

    def test_signature(self):
        assert self.main_chunk.signature == "int main()"

class TestTreesitterChunker_cpp_Functions:

    def setup_method(self):
        chunks = build_test_chunks(test_cases_cpp / "hello.cpp", RAGChunkerOptions.OnlyTsChunks())
        assert len(chunks) == 1
        self.first_chunk = chunks[0]

    def test_code(self):
        expected_main_text = "int main() {\n    std::cout << \"Hello, World!\" << std::endl;\n    return 0;\n}"
        assert self.first_chunk.text == expected_main_text

    def test_signature(self):
        assert self.first_chunk.signature == "int main()"

class TestTreesitterChunker_csharp_Functions:

    def setup_method(self):
        # node.type='local_function_statement'
        #  child.type='modifier'
        #    text='static'
        #  child.type='predefined_type'
        #    text='void'
        #  child.type='identifier'
        #    text='Greeting'
        #  child.type='parameter_list'
        #    text='(string name)'
        #  child.type='block'
        #    text='{\n    Console.WriteLine($"Hello, {name}!");\n}'

        chunks = build_test_chunks(test_cases_csharp / "Program.cs", RAGChunkerOptions.OnlyTsChunks())
        assert len(chunks) == 1
        self.first_chunk = chunks[0]

    def test_code(self):
        expected_main_text = "static void Greeting(string name)\n{\n    Console.WriteLine($\"Hello, {name}!\");\n}"
        assert self.first_chunk.text == expected_main_text

    def test_signature(self):
        assert self.first_chunk.signature == "static void Greeting(string name)"

class TestTreesitterChunker_rust_Functions:

    def setup_method(self):

        chunks = build_test_chunks(test_cases_rust / "hello.rs", RAGChunkerOptions.OnlyTsChunks())
        assert len(chunks) == 2
        self.first_chunk = chunks[0]
        self.second_chunk = chunks[1]

    def test_code(self):
        expected_main_text = "fn main() {\n    println!(\"Hello, world!\");\n    greeting();\n}"
        assert self.first_chunk.text == expected_main_text

        expected_greeting_text = "fn greeting() {\n    println!(\"Greetings, user!\");\n}"
        assert self.second_chunk.text == expected_greeting_text

    def test_signature(self):
        assert self.first_chunk.signature == "fn main()"
        assert self.second_chunk.signature == "fn greeting()"
