import asyncio
from pathlib import Path

from index import workspace
from chunks.chunker import *
from index.storage import Chunk

# * set root dir for relative paths
my_dir = Path(__file__).absolute().parent
test_cases = my_dir / "test_cases"
test_cases_xonsh = test_cases / "treesitter" / "xonsh"

asyncio.run(workspace.from_repo_root(my_dir))


def build_test_chunks(path: Path, options: RAGChunkerOptions) -> list[Chunk]:
    ts_chunks, _ = build_ts_chunks_from_source_bytes(path, "fake_hash", path.read_bytes(), options)
    return ts_chunks


class TestTsChunker_Xonsh_Functions:
    """ top-level `def` blocks are function_definition nodes (already recognized).
    The signature stops at the body (block) node. """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_xonsh / "hello.xsh", RAGChunkerOptions.OnlyTsChunks())

    def test_chunks_found(self):
        assert len(self.chunks) == 5

    def test_top_level_func_chunked(self):
        greet = self.chunks[0]
        assert greet.text == "def greet(name):\n    return \"Hello, \" + name"
        assert greet.signature == "def greet(name):"

    def test_main_func_chunked(self):
        main = self.chunks[4]
        assert main.text == "def main():\n    person = Person(\"Ada\")\n    print(greet(person.full_name(\"Lovelace\")))"
        assert main.signature == "def main():"


class TestTsChunker_Xonsh_Class:
    """ class_definition is recognized whole (with its methods); methods
    (function_definition) are chunked individually. """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_xonsh / "hello.xsh", RAGChunkerOptions.OnlyTsChunks())

    def test_class_chunked_whole(self):
        person = self.chunks[1]
        assert person.text == "class Person:\n    def __init__(self, name):\n        self.name = name\n\n    def full_name(self, last):\n        return self.name + \" \" + last"
        assert person.signature == "class Person:"

    def test_methods_chunked(self):
        init = self.chunks[2]
        assert init.text == "def __init__(self, name):\n        self.name = name"
        assert init.signature == "def __init__(self, name):"

        full_name = self.chunks[3]
        assert full_name.text == "def full_name(self, last):\n        return self.name + \" \" + last"
        assert full_name.signature == "def full_name(self, last):"


class TestTsChunker_Xonsh_Decorated:
    """ decorators wrap the def in a decorated_definition node. The inner
    function_definition is still recognized and chunked (the decorator line is
    NOT yet attached to the chunk). """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_xonsh / "decorated.xsh", RAGChunkerOptions.OnlyTsChunks())

    def test_chunks_found(self):
        assert len(self.chunks) == 3

    def test_plain_func_chunked(self):
        add = self.chunks[0]
        assert add.text == "def add(a, b):\n    return a + b"
        assert add.signature == "def add(a, b):"

    def test_decorated_func_chunked(self):
        double = self.chunks[1]
        assert double.text == "def double(x):\n    return x * 2"
        assert double.signature == "def double(x):"

        read_only = self.chunks[2]
        assert read_only.text == "def read_only():\n    return 42"
        assert read_only.signature == "def read_only():"
