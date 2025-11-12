from dataclasses import dataclass
import hashlib
import logging
import os
from pathlib import Path
from typing import Iterator

from tree_sitter import Node

from lsp.chunks.identified import IdentifiedChunk
from lsp.chunks.ts.lua import attach_doc_comments
from lsp.chunks.ts.py import attach_decorators
from lsp.chunks.uncovered import UncoveredCode, build_uncovered_intervals
from lsp.storage import Chunk, ChunkType, FileStat, chunk_id_for, chunk_id_to_faiss_id, chunk_id_with_columns_for
from lsp.logs import get_logger, printtmp
from lsp.chunks.parsers import get_cached_parser_for_path
from lsp.chunks.ansi import *

logger = get_logger(__name__)
logger.setLevel(logging.DEBUG)

# TODO! flagging good/bad query results
# - it would help to have a way to quantify my chunking/querying effectiveness... vs just gut feeling on future searches
# - thus flagging good/bad results would provide a supervised way to quantify effectiveness
# - TODO what do I need to capture?
#   - git commit ID so I have original code and can align matches to the original code positions?
# - TODO add keymap in semantic grep extension to flag good/bad
# - TODO add keymap for FIM generation that I attribute to RAG context as good/bad
#   - same idea in AskToolUse and AskRewrite

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

def build_chunks_from_lines(path: Path, file_hash: str, lines: list[str], options: RAGChunkerOptions) \
    -> list[Chunk]:
    """ use lines as the source to build all chunks
        DOES NOT READ FILE at path
        path is just for building chunk results
    """
    chunks = []

    ts_chunks = []
    uncovered_code = []
    if options.enable_ts_chunks:
        source_bytes = "".join(lines).encode("utf-8")
        ts_chunks, uncovered_code = build_ts_chunks_from_source_bytes(path, file_hash, source_bytes, options)
        chunks.extend(ts_chunks)

    if options.enable_line_range_chunks:
        # TODO! I am noticing good results from line ranges (sliding windows) that aren't coming up in ts_chunk equivalents when ts_chunks are BIG (i.e. huge functions)
        #    IIGC b/c those functions are BIG and so it's missing some of the granularity to identify a subset of a function
        #    I might want to keep sliding window overlaps UNTIL I add some sort of sliding window breaking up of functions?
        #    - OR should I not index a full function if it spans too many lines? and leave it uncovered for sliding window only?
        #      - IOTW only exclude small functions from line range chunking?
        #    TLDR: when I use uncovered code ONLY for line ranges... ouch I lose the ability to query large functions
        #
        can_use_uncoverd_code = path.suffix in {".py", ".lua"}
        # can_use_uncoverd_code = False # uncomment to block all use of uncovered code
        if can_use_uncoverd_code and len(ts_chunks) > 0:
            chunks.extend(build_line_range_chunks_from_uncovered_code(path, file_hash, uncovered_code))
        else:
            # if no treesitter chunks, fallback to sliding window for all of it (regardless why no chunks)
            chunks.extend(build_line_range_chunks_from_lines(path, file_hash, lines))

    return chunks

def build_line_range_chunks_from_uncovered_code(path: Path, file_hash: str, uncovered_code: list[UncoveredCode]) -> Iterator[Chunk]:
    # FYI quick idea for using sliding window on each contiguous section of covered code:

    for idx, uncovered in enumerate(uncovered_code):
        if uncovered.is_whitespace_or_empty():
            continue
        lines = uncovered.text.splitlines(keepends=True)  # TODO! test case to ensure trailing \n preserved (and/or other line endings? \r\n, etc?)
        for chunk in build_line_range_chunks_from_lines(path, file_hash, lines):
            # TODO! add a few integration tests
            # TODO VERIFY start/end lines are adjusted to match relative position in actual file
            chunk.start_line0 += uncovered.start_line_base0()
            chunk.end_line0 += uncovered.start_line_base0()
            # recompute chunk id w/ corrected start/end line
            chunk_id = chunk_id_for(path, chunk.type, chunk.start_line0, chunk.end_line0, file_hash)
            chunk.id = chunk_id
            chunk.id_int = str(chunk_id_to_faiss_id(chunk_id))
            chunk.type = ChunkType.UNCOVERED_CODE
            yield chunk

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
            chunk_type = ChunkType.LINES
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

def build_ts_chunks_from_source_bytes(path: Path, file_hash: str, source_bytes: bytes, options: RAGChunkerOptions) \
    -> tuple[list[Chunk], list[UncoveredCode]]:

    # IDEA: try semantic chunking within large nodes (i.e. functions)?
    # - split into smaller chunks, compute their embeddings
    # - compute cosine similiarity of neighbors (dot product)
    # - if within threshold, combine (up to a chunk size limit)
    #
    # OR, would a sliding window work about as well?

    parser, parser_language = get_cached_parser_for_path(path)
    if parser is None:
        return [], []

    with logger.timer(f'parse_ts {path}'):
        # TODO! do I need to call parser.reset() to be safe?
        #   if there was a failure on a previous call to .parse() then IIUC subseuqent calls to parse() will attempt resumption?
        tree = parser.parse(source_bytes)

    def get_signature_stop_on(node, stop_node_type) -> str:
        stop_before_node = None
        for child in node.children:
            if child.type == stop_node_type:
                stop_before_node = child
                break

        if not stop_before_node:
            return f"--- unexpected {stop_node_type=} NOT FOUND ---"

        return source_bytes[node.start_byte:stop_before_node.start_byte] \
                .decode("utf-8", errors="replace") \
                .strip()

    def get_signature(node) -> str:
        if node.type == 'type_alias_declaration':
            # - type_alias_declaration == typescript
            # FYI in this case, I could do stop on type=="type_identifier" INSTEAD of stop before type=="="
            return get_signature_stop_on(node, "=")
        elif node.type == 'interface_declaration':
            # typescript
            return get_signature_stop_on(node, "interface_body")
        elif node.type == 'enum_declaration':
            # typescript
            return get_signature_stop_on(node, "enum_body")
        elif node.type == 'class_declaration':
            # - class_declaration == typescript
            return get_signature_stop_on(node, "class_body")
        elif node.type.find("class_definition") >= 0:
            # - class_definition == python (and lua?)
            return get_signature_stop_on(node, "block")
        else:
            return f"--- TODO {node.type} ---"

    def get_function_signature(node) -> str:
        # printtmp(f'\n [red]{node.type=}[/]')

        sig = None

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

        stop_before_node = None
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
        # if node.type.find('function') <= 0:
        #     return
        #
        logger.debug(f'unhandled node.type: {GREEN}{node.type}{RESET}')
        logger.debug_no_markup(str(node.text).replace("\\n", "\n"))

    def identify_chunks(node: Node, collected_parent: bool = False, level: int = 0) -> Iterator[IdentifiedChunk]:
        # TODO make this async and take it all the way up to the indexer level (which is already async, and is already batched)... so I could actually batch process end to end and do some sort of localized grouping on chunk size still over in the indexer (embedder)... interesting!
        #  would also allow me to get the embedding server going sooner (probably boost meaningful responsiveness when I have small batches of updates (i.e. after git commit) where starting the embedding server sooner would cut material % of time off overall for Time to First Embedding Batch
        #  could even use multi worker arch to prepare next batch while server is embedding first batch(es) - producer/consumer?

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
            # - extract indentation level from start of line (before matched node)
            #   - perhaps take the entire start line and end line?
            #   - right now nodes that are indented (i.e. nested function),
            #     the first line (signature) has incorrect indentation!
            #     b/c treesitter selects the start of the signature (not the line)
            #
            #   - applies to treesitter chunks
            #   - applies to uncovered_code chunks
            # print(node.prev_sibling)
            chunk = IdentifiedChunk(
                sibling_nodes=[node],
                signature=get_function_signature(node),
            )
            if parser_language == "lua":
                attach_doc_comments(node, chunk.sibling_nodes)
            if parser_language == "python":
                attach_decorators(node, chunk.sibling_nodes)
            yield chunk
            collected_parent = True

        elif node.type in [
                "class_definition",
                "class_declaration",
                "type_alias_declaration",
                "interface_declaration",
                "enum_declaration",
        ]:
            # ts type_alias_declaration https://www.typescriptlang.org/docs/handbook/2/everyday-types.html#type-aliases
            # ts interface_declaration https://www.typescriptlang.org/docs/handbook/2/everyday-types.html#interfaces
            # ts enum_declaration https://www.typescriptlang.org/docs/handbook/enums.html
            #
            # typescript class_declaration
            # python ?
            chunk = IdentifiedChunk(
                sibling_nodes=[node],
                signature=get_signature(node),
            )
            yield chunk
            collected_parent = True
            if parser_language == "python":
                attach_decorators(node, chunk.sibling_nodes)

        elif logger.isEnabledForDebug() and not collected_parent:
            debug_uncollected_node(node)

        for child in node.children:
            yield from identify_chunks(child, collected_parent, level + 1)

    # PRN batch process chunks?
    identified_chunks = list(identify_chunks(tree.root_node))
    uncovered_code = build_uncovered_intervals(tree, source_bytes, identified_chunks, path)

    ts_chunks = []
    for chunk in identified_chunks:

        # FYI assume contiguous and ordered nodes (so first is literally first in doc, last is last)
        first = chunk.sibling_nodes[0]
        last = chunk.sibling_nodes[-1]

        # ?? allow non-contiguous nodes (i.e. top level module statements if I were to use treesitter to find and aggrgate these instead of sliding window)
        start_line_base0 = first.start_point[0]
        start_column_base0 = first.start_point[1]
        end_line_base0 = last.end_point[0]
        end_column_base0 = last.end_point[1]

        chunk_type = ChunkType.TREESITTER
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

    return ts_chunks, uncovered_code
