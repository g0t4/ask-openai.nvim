import asyncio
from pathlib import Path

from index import workspace
from chunks.chunker import *
from index.storage import Chunk

# * set root dir for relative paths
my_dir = Path(__file__).absolute().parent
test_cases = my_dir / "test_cases"
test_cases_java = test_cases / "treesitter" / "java"

asyncio.run(workspace.from_repo_root(my_dir))


def build_test_chunks(path: Path, options: RAGChunkerOptions) -> list[Chunk]:
    ts_chunks, _ = build_ts_chunks_from_source_bytes(path, "fake_hash", path.read_bytes(), options)
    return ts_chunks


class TestTsChunker_Java_Class:
    """ class_declaration is already recognized (whole class) and its methods
    (method_declaration) are chunked individually. Constructors
    (constructor_declaration) are NOT yet recognized. """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_java / "classes.java", RAGChunkerOptions.OnlyTsChunks())

    def test_chunks_found(self):
        assert len(self.chunks) == 4

    def test_class_chunked_whole(self):
        cls = self.chunks[0]
        assert cls.text == "public class Person {\n    private String name;\n\n    public Person(String name) {\n        this.name = name;\n    }\n\n    public String getName() {\n        return name;\n    }\n\n    public static Person create(String name) {\n        return new Person(name);\n    }\n}"
        assert cls.signature == "public class Person"

    def test_constructor_chunked(self):
        ctor = self.chunks[1]
        assert ctor.text == "public Person(String name) {\n        this.name = name;\n    }"
        assert ctor.signature == "public Person(String name)"

    def test_methods_chunked(self):
        assert self.chunks[2].text == "public String getName() {\n        return name;\n    }"
        assert self.chunks[2].signature == "public String getName()"
        assert self.chunks[3].text == "public static Person create(String name) {\n        return new Person(name);\n    }"
        assert self.chunks[3].signature == "public static Person create(String name)"


class TestTsChunker_Java_Record:
    """ record_declaration (Java 16+) is NOT yet recognized as a whole type. """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_java / "records.java", RAGChunkerOptions.OnlyTsChunks())

    def test_chunks_found(self):
        assert len(self.chunks) == 2

    def test_record_chunked_whole(self):
        rec = self.chunks[0]
        assert rec.text == "public record Point(int x, int y) {\n    public int sum() {\n        return x + y;\n    }\n}"
        assert rec.signature == "public record Point(int x, int y)"

    def test_record_method_chunked(self):
        method = self.chunks[1]
        assert method.text == "public int sum() {\n        return x + y;\n    }"
        assert method.signature == "public int sum()"


class TestTsChunker_Java_Interface:
    """ interface_declaration is already recognized whole. Abstract methods
    (no body) previously produced a bogus signature -- now they fall back to
    the full declaration text. """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_java / "interfaces.java", RAGChunkerOptions.OnlyTsChunks())

    def test_chunks_found(self):
        assert len(self.chunks) == 3

    def test_interface_chunked_whole(self):
        iface = self.chunks[0]
        assert iface.text == "public interface Shape {\n    double area();\n    default double scaled(double factor) {\n        return area() * factor;\n    }\n}"
        assert iface.signature == "public interface Shape"

    def test_abstract_method_signature(self):
        # bodyless method_declaration: signature falls back to the full declaration
        abstract = self.chunks[1]
        assert abstract.text == "double area();"
        assert abstract.signature == "double area();"

    def test_default_method_chunked(self):
        default_method = self.chunks[2]
        assert default_method.text == "default double scaled(double factor) {\n        return area() * factor;\n    }"
        assert default_method.signature == "default double scaled(double factor)"


class TestTsChunker_Java_Enum:
    """ enum_declaration is already recognized whole; enum methods chunked. """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_java / "enums.java", RAGChunkerOptions.OnlyTsChunks())

    def test_chunks_found(self):
        assert len(self.chunks) == 2

    def test_enum_chunked_whole(self):
        enum = self.chunks[0]
        assert enum.text == "public enum Direction {\n    UP,\n    DOWN;\n\n    public int code() {\n        return this.ordinal();\n    }\n}"
        assert enum.signature == "public enum Direction"

    def test_enum_method_chunked(self):
        method = self.chunks[1]
        assert method.text == "public int code() {\n        return this.ordinal();\n    }"
        assert method.signature == "public int code()"


class TestTsChunker_Java_AnnotationType:
    """ annotation_type_declaration is NOT yet recognized. """

    def setup_method(self):
        self.chunks = build_test_chunks(test_cases_java / "annotations.java", RAGChunkerOptions.OnlyTsChunks())

    def test_chunks_found(self):
        assert len(self.chunks) == 1

    def test_annotation_type_chunked(self):
        ann = self.chunks[0]
        assert ann.text == "public @interface MyAnnotation {\n    String value();\n}"
        assert ann.signature == "public @interface MyAnnotation"
