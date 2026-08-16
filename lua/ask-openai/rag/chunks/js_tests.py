import asyncio
from pathlib import Path

from index import workspace
from chunks.chunker import *
from index.storage import Chunk

# * set root dir for relative paths
my_dir = Path(__file__).absolute().parent
test_cases = my_dir / "test_cases"
test_cases_javascript = test_cases / "treesitter" / "javascript"

asyncio.run(workspace.from_repo_root(my_dir))


def build_test_chunks(path: Path, options: RAGChunkerOptions) -> list[Chunk]:
    ts_chunks, _ = build_ts_chunks_from_source_bytes(path, "fake_hash", path.read_bytes(), options)
    return ts_chunks


class TestTsChunker_JavaScript_TopLevelFunctions:
    """ `function foo() {}` is a function_declaration (already recognized).
    `function* gen() {}` is a generator_function_declaration (NOT yet recognized). """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_javascript / "functions.js", RAGChunkerOptions.OnlyTsChunks())

    def test_chunks_found(self):
        assert len(self.chunks) == 2

    def test_function_declaration_chunked(self):
        add = self.chunks[0]
        assert add.text == "function add(a, b) {\n    return a + b;\n}"
        assert add.signature == "function add(a, b)"

    def test_generator_function_declaration_chunked(self):
        gen = self.chunks[1]
        assert gen.text == "function* range(start, end) {\n    for (let i = start; i < end; i++) {\n        yield i;\n    }\n}"
        assert gen.signature == "function* range(start, end)"


class TestTsChunker_JavaScript_FunctionExpressions:
    """ `const f = function(a, b) { ... }` is a function_expression under a
    variable_declarator. NOT yet recognized. The whole declaration (incl. the
    variable name) is the semantic unit. """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_javascript / "expressions.js", RAGChunkerOptions.OnlyTsChunks())

    def test_chunks_found(self):
        assert len(self.chunks) == 3

    def test_const_function_expression(self):
        chunk = self.chunks[0]
        assert chunk.text == "const add = function(a, b) {\n    return a + b;\n};"
        assert chunk.signature == "const add = function(a, b)"

    def test_let_function_expression(self):
        chunk = self.chunks[1]
        assert chunk.text == "let multiply = function(a, b) {\n    return a * b;\n};"
        assert chunk.signature == "let multiply = function(a, b)"

    def test_var_function_expression(self):
        chunk = self.chunks[2]
        assert chunk.text == "var divide = function(a, b) {\n    return a / b;\n};"
        assert chunk.signature == "var divide = function(a, b)"


class TestTsChunker_JavaScript_ArrowFunctions:
    """ `const f = (a, b) => { ... }` is an arrow_function. NOT yet recognized.
    Covers both block-bodied and concise (expression) bodies. """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_javascript / "arrows.js", RAGChunkerOptions.OnlyTsChunks())

    def test_chunks_found(self):
        assert len(self.chunks) == 2

    def test_block_body_arrow(self):
        chunk = self.chunks[0]
        assert chunk.text == "const add = (a, b) => {\n    return a + b;\n};"
        assert chunk.signature == "const add = (a, b) =>"

    def test_concise_body_arrow(self):
        chunk = self.chunks[1]
        # concise body has no statement_block, so signature is the whole declaration
        assert chunk.text == "const square = x => x * x;"
        assert chunk.signature == "const square = x => x * x"


class TestTsChunker_JavaScript_Classes:
    """ `class Foo { ... }` is a class_declaration (already recognized).
    Methods (method_definition) live inside the class_body and are part of the
    single class chunk -- not emitted as standalone chunks. """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_javascript / "classes.js", RAGChunkerOptions.OnlyTsChunks())

    def test_chunks_found(self):
        assert len(self.chunks) == 1

    def test_class_chunked_whole(self):
        cls = self.chunks[0]
        assert cls.text == "class Calculator {\n    add(a, b) {\n        return a + b;\n    }\n\n    static multiply(a, b) {\n        return a * b;\n    }\n\n    get value() {\n        return this._value;\n    }\n}"
        assert cls.signature == "class Calculator"
