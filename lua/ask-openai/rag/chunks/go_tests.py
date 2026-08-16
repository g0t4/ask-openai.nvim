import asyncio
from pathlib import Path

from index import workspace
from chunks.chunker import *
from index.storage import Chunk

# * set root dir for relative paths
my_dir = Path(__file__).absolute().parent
test_cases = my_dir / "test_cases"
test_cases_go = test_cases / "treesitter" / "go"

asyncio.run(workspace.from_repo_root(my_dir))


def build_test_chunks(path: Path, options: RAGChunkerOptions) -> list[Chunk]:
    ts_chunks, _ = build_ts_chunks_from_source_bytes(path, "fake_hash", path.read_bytes(), options)
    return ts_chunks


class TestTsChunker_Go_Functions:
    """ top-level func declarations are function_declaration nodes (already recognized) """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_go / "hello.go", RAGChunkerOptions.OnlyTsChunks())

    def test_chunks_found(self):
        assert len(self.chunks) >= 4

    def test_top_level_func_code(self):
        greeting_chunk = self.chunks[0]
        assert greeting_chunk.text == """func Greeting(name string) string {
	return fmt.Sprintf("Hello, %s!", name)
}"""

    def test_top_level_func_signature(self):
        greeting_chunk = self.chunks[0]
        assert greeting_chunk.signature == "func Greeting(name string) string"


class TestTsChunker_Go_Methods:
    """ methods (func with receiver) are method_declaration nodes (NOT yet recognized) """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_go / "hello.go", RAGChunkerOptions.OnlyTsChunks())

    def test_value_receiver_method_chunked(self):
        full_name = self.chunks[2]
        assert full_name.text == """func (p Person) FullName() string {
	return p.FirstName + " " + p.LastName
}"""
        assert full_name.signature == "func (p Person) FullName() string"

    def test_pointer_receiver_method_chunked(self):
        set_last_name = self.chunks[3]
        assert set_last_name.text == """func (p *Person) SetLastName(name string) {
	p.LastName = name
}"""
        assert set_last_name.signature == "func (p *Person) SetLastName(name string)"


class TestTsChunker_Go_Struct:
    """ struct is type_spec under type_declaration (NOT yet recognized) """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_go / "hello.go", RAGChunkerOptions.OnlyTsChunks())

    def test_struct_chunked(self):
        person = self.chunks[1]
        assert person.text == """type Person struct {
	FirstName string
	LastName  string
}"""
        assert person.signature == "type Person struct"


class TestTsChunker_Go_Interfaces:
    """ interfaces are type_spec under type_declaration (NOT yet recognized) """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_go / "hello.go", RAGChunkerOptions.OnlyTsChunks())

    def test_interface_chunked(self):
        shape = self.chunks[4]
        assert shape.text == """type Shape interface {
	Area() float64
}"""
        assert shape.signature == "type Shape interface"


class TestTsChunker_Go_TypeAlias:
    """ type alias (type ID = string) (NOT yet recognized) """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_go / "hello.go", RAGChunkerOptions.OnlyTsChunks())

    def test_type_alias_chunked(self):
        type_id = self.chunks[6]
        assert type_id.text == "type ID = string"
        assert type_id.signature == "type ID"


class TestTsChunker_Go_GroupedTypes:
    """ multiple type_specs under one type_declaration: emit BOTH a grouped chunk
    AND one chunk per type.

    `type ( A; B; C )` produces: [grouped chunk, A, B, C].
    `type Single int` (a single type_declaration) produces just [Single].
    """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_go / "grouped_types.go", RAGChunkerOptions.OnlyTsChunks())

    def test_grouped_emits_group_plus_individuals(self):
        assert [c.signature for c in self.chunks] == [
            "type A, B, C",
            "type A int",
            "type B string",
            "type C struct",
            "type Single int",
        ]

    def test_grouped_chunk_has_whole_group_text(self):
        assert self.chunks[0].text == "type (\n\tA int\n\tB string\n\tC struct {\n\t\tX int\n\t\tY int\n\t}\n)"

    def test_individual_type_chunks_text_is_raw_node(self):
        # chunk text is exactly the node's byte range -- no fabricated 'type ' prefix
        assert self.chunks[1].text == "A int"
        assert self.chunks[2].text == "B string"
        assert self.chunks[3].text == "C struct {\n\t\tX int\n\t\tY int\n\t}"
        assert self.chunks[4].text == "type Single int"


class TestTsChunker_Go_EmptyTypeGroup:
    """ `type ()` is valid go but declares zero types => must yield zero chunks. """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_go / "empty_type_group.go", RAGChunkerOptions.OnlyTsChunks())

    def test_empty_type_group_yields_no_chunk(self):
        assert self.chunks == []



class TestTsChunker_Go_Generics:
    """ go generic types and generic methods. """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_go / "generics.go", RAGChunkerOptions.OnlyTsChunks())

    def test_generic_struct(self):
        # signature should include the type parameter list
        assert self.chunks[0].signature == "type List[T any] struct"
        assert self.chunks[0].text == """type List[T any] struct {
	items []T
}"""

    def test_generic_method(self):
        assert self.chunks[1].signature == "func (l *List[T]) Len() int"

    def test_multi_type_param_struct(self):
        assert self.chunks[2].signature == "type Pair[K comparable, V any] struct"


class TestTsChunker_Go_GroupedAlias:
    """ a type_alias inside a grouped type_declaration. """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_go / "grouped_alias.go", RAGChunkerOptions.OnlyTsChunks())

    def test_grouped_alias_emits_group_plus_individuals(self):
        assert [c.signature for c in self.chunks] == [
            "type A, ID",
            "type A int",
            "type ID",
        ]
