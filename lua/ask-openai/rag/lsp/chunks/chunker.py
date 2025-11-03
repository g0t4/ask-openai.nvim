from dataclasses import dataclass
import hashlib
import logging
import os
from pathlib import Path

from tree_sitter import Node

from lsp.chunks.lua import insert_previous_doc_comment
from lsp.chunks.uncovered import debug_uncovered_nodes
from lsp.storage import Chunk, FileStat, chunk_id_for, chunk_id_to_faiss_id, chunk_id_with_columns_for
from lsp.logs import get_logger, printtmp
from lsp.chunks.parsers import get_cached_parser_for_path

logger = get_logger(__name__)
# logger.setLevel(logging.DEBUG)

@dataclass
class RAGChunkerOptions:
    enable_ts_chunks: bool = False
    enable_line_range_chunks: bool = True

    @staticmethod
    def OnlyLineRangeChunks():
        return RAGChunkerOptions(enable_line_range_chunks=True, enable_ts_chunks=False)

    @staticmethod
    def OnlyTsChunks():
        return RAGChunkerOptions(enable_line_range_chunks=False, enable_ts_chunks=True)

    @staticmethod
    def ProductionOptions():
        return RAGChunkerOptions(enable_line_range_chunks=True, enable_ts_chunks=True)

def get_file_hash(file_path: Path | str) -> str:
    file_path = Path(file_path)
    # PRN is this slow? or ok?
    hasher = hashlib.sha256()
    with open(file_path, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hasher.update(chunk)
    return hasher.hexdigest()

def get_file_hash_from_lines(lines: list[str]) -> str:
    hasher = hashlib.sha256()
    # FYI lines have \n on end from LSP... so don't need to join w/ that between lines
    for line in lines:
        hasher.update(line.encode())
    return hasher.hexdigest()

def get_file_stat(file_path: Path | str) -> FileStat:
    file_path = Path(file_path)

    stat = file_path.stat()
    return FileStat(
        mtime=stat.st_mtime,
        size=stat.st_size,
        hash=get_file_hash(file_path),
        path=str(file_path)  # for serializing and reading by LSP
    )

def build_chunks_from_file(path: Path | str, file_hash: str, options: RAGChunkerOptions) -> list[Chunk]:
    path = Path(path)

    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        # each line has trailing newline (it is not stripped out)
        lines = f.readlines()
        return build_chunks_from_lines(path, file_hash, lines, options)

def build_chunks_from_lines(path: Path, file_hash: str, lines: list[str], options: RAGChunkerOptions):
    """ use lines as the source to build all chunks
        DOES NOT READ FILE at path
        path is just for building chunk results
    """
    chunks = []

    if options.enable_line_range_chunks:
        chunks.extend(build_line_range_chunks_from_lines(path, file_hash, lines))

    if options.enable_ts_chunks:
        source_bytes = "".join(lines).encode("utf-8")
        chunks.extend(build_ts_chunks_from_source_bytes(path, file_hash, source_bytes, options))

    return chunks

def build_line_range_chunks_from_lines(path: Path, file_hash: str, lines: list[str]) -> list[Chunk]:
    """ only builder for line range chunks (thus denominated in lines only)"""

    # when the time comes, figure out how to alter these:
    lines_per_chunk = 20
    overlap = 5
    step = lines_per_chunk - overlap

    # assertions so I can alter these params
    assert lines_per_chunk > 0, "lines_per_chunk must be > 0"
    assert 0 <= overlap < lines_per_chunk, "overlap must be in [0, lines_per_chunk)"
    assert 0 < step

    num_lines = len(lines)

    def iter_chunks():

        for idx, start_line_base0 in enumerate(range(0, num_lines, step)):
            end_line_exclusive_base0 = min(start_line_base0 + lines_per_chunk, num_lines)  # line after last line (saves from +-1 footgun)
            num_lines_in_this_chunk = end_line_exclusive_base0 - start_line_base0
            if num_lines_in_this_chunk <= overlap and idx > 0:
                # skip if chunk is only the overlap with prior chunk
                break

            end_line_base0 = end_line_exclusive_base0 - 1
            chunk_type = "lines"
            chunk_id = chunk_id_for(path, chunk_type, start_line_base0, end_line_base0, file_hash)
            yield Chunk(
                id=chunk_id,
                id_int=str(chunk_id_to_faiss_id(chunk_id)),
                text="".join(lines[start_line_base0:end_line_exclusive_base0]),  # slice is not end-inclusive
                file=str(path),
                start_line0=start_line_base0,
                start_column0=0,  # always the first column for line ranges
                end_line0=end_line_base0,
                end_column0=None,
                type=chunk_type,
                file_hash=file_hash,
                signature="",  # TODO
            )

    return list(iter_chunks())

@dataclass
class IdentifiedChunk:
    # i.e. when primary has doc_comments/annotations/decorators before it, these are then siblings and there is not single node
    sibling_nodes: list[Node]
    signature: str = ""

def build_ts_chunks_from_source_bytes(path: Path, file_hash: str, source_bytes: bytes, options: RAGChunkerOptions) -> list[Chunk]:

    parser, parser_language = get_cached_parser_for_path(path)
    if parser is None:
        return []

    with logger.timer(f'parse_ts {path}'):
        tree = parser.parse(source_bytes)

    def get_class_signature(node) -> str:
        sig = None
        stop_before_node = None

        stop_node_type = None
        # - class_declaration == typescript
        # - class_definition == python (and lua?)
        if node.type == 'class_declaration':
            stop_node_type = "class_body"
        elif node.type.find("class_definition") >= 0:
            stop_node_type = "block"
        else:
            return f"--- TODO {node.type} ---"

        for child in node.children:
            # text = child.text.decode("utf-8", errors="replace")
            # printtmp(f'  {child.type=}\n    {text=}')
            if child.type == stop_node_type:
                stop_before_node = child
                break

        if not stop_before_node:
            return f"--- unexpected {stop_node_type=} NOT FOUND ---"

        return source_bytes[node.start_byte:stop_before_node.start_byte] \
                .decode("utf-8", errors="replace") \
                .strip()

    def get_function_signature(node) -> str:
        # printtmp(f'\n [red]{node.type=}[/]')

        sig = None
        stop_before_node = None

        # algorithm: signature == copy everything until start of the function body
        # - function_declaration => statement_block (typescript)
        # - function_definition => block (lua, python)
        #   function_definition => compound_statement (c, cpp)
        # - local_function_statement => block (csharp)
        # - function_item => block (rust)
        stop_node_types = [
            "statement_block",
            "block",
            "compound_statement",
        ]

        for child in node.children:
            text = child.text.decode("utf-8", errors="replace")
            # printtmp(f'  {child.type=}\n    {text=}')
            if child.type in stop_node_types:
                stop_before_node = child
                break

        if not stop_before_node:
            return f"--- unexpected {stop_node_types=} NOT FOUND ---"

        # PRN strip 2+ lines that are purely comments?

        return source_bytes[node.start_byte:stop_before_node.start_byte] \
                .decode("utf-8", errors="replace") \
                .strip()

    def debug_uncollected_node(node):
        # use node type filter to find specific nodes
        if node.type.find('function') <= 0:
            return

        logger.debug(f'node type not handled: {node.type}')
        logger.debug(str(node.text).replace("\\n", "\n"))
        logger.debug("")

    def identify_chunks(node: Node, collected_parent: bool = False, level: int = 0) -> list[IdentifiedChunk]:

        chunks: list[IdentifiedChunk] = []

        if node.type in [
                "function_definition",
                "local_function_definition_statement",
                "function_definition_statement",
                "local_function_statement",
                "function_declaration",
                "function_item",
        ]:
            # ts: function_declaration
            # lua: function_definition == anonymous functions
            # python: function_definition == named functions
            # lua: named functions (local_function_definition_statement/local vs function_definition_statement/global)
            # csharp: local_function_statement
            # rust: function_item
            #
            # TODO:
            # - lua functions, grab --- triple dash comments before function (until blank line)
            # - py functions, decorators i.e. @dataclass right before function signature
            # print(node.prev_sibling)
            chunk = IdentifiedChunk(
                sibling_nodes=[node],
                signature=get_function_signature(node),
            )
            if parser_language == "lua":
                insert_previous_doc_comment(node, chunk.sibling_nodes)

            chunks.append(chunk)
            collected_parent = True
        elif node.type in [
                "class_definition",
                "class_declaration",
        ]:
            # typescript class_declaration
            # python
            chunk = IdentifiedChunk(
                sibling_nodes=[node],
                signature=get_class_signature(node),
            )
            chunks.append(chunk)
            collected_parent = True
        elif logger.isEnabledForDebug() and not collected_parent:
            debug_uncollected_node(node)

        for child in node.children:
            nested_chunks = identify_chunks(child, collected_parent, level + 1)
            chunks.extend(nested_chunks)

        return chunks

    identified_chunks = identify_chunks(tree.root_node)
    debug_uncovered_nodes(tree, source_bytes, identified_chunks, path)

    ts_chunks = []
    for chunk in identified_chunks:

        # FYI assume contiguous and ordered nodes (so first is literally first in doc, last is last)
        first = chunk.sibling_nodes[0]
        last = chunk.sibling_nodes[-1]

        start_line_base0 = first.start_point[0]
        start_column_base0 = first.start_point[1]
        end_line_base0 = last.end_point[0]
        end_column_base0 = last.end_point[1]

        chunk_type = "ts"
        chunk_id = chunk_id_with_columns_for(path, chunk_type, start_line_base0, start_column_base0, end_line_base0, end_column_base0, file_hash)

        # TODO! add test cases that cover multi node at the chunk level
        text = source_bytes[first.start_byte:last.end_byte] \
                .decode("utf-8", errors="replace")

        chunk = Chunk(
            id=chunk_id,
            id_int=str(chunk_id_to_faiss_id(chunk_id)),
            text=text,
            file=str(path),
            start_line0=start_line_base0,
            start_column0=start_column_base0,
            end_line0=end_line_base0,
            end_column0=end_column_base0,
            type=chunk_type,
            file_hash=file_hash,
            signature=chunk.signature or "",
        )

        ts_chunks.append(chunk)

    return ts_chunks
