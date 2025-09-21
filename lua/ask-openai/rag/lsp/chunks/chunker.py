from dataclasses import dataclass
import hashlib
from pathlib import Path
from tree_sitter import Node
from tree_sitter_languages import get_language, get_parser

from lsp.storage import Chunk, FileStat, chunk_id_for, chunk_id_to_faiss_id, chunk_id_with_columns_for
from lsp.logs import get_logger

logger = get_logger(__name__)

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
    # lines is the common denominator between Language Server (TextDocument.lines)
    #  and I was already using readlines() in when building from files on disk (indexer)
    chunks = []

    if options.enable_line_range_chunks:
        chunks.extend(build_line_range_chunks_from_lines(path, file_hash, lines))

    if options.enable_ts_chunks:
        # TODO add indexer tests that include ts_chunking (maybe even disable line range chunking)
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

parsers_by_language = {}

def get_cached_parser(language):
    if language in parsers_by_language:
        return parsers_by_language[language]

    with logger.timer('get_parser' + language):
        parser = get_parser(language)
        parsers_by_language[language] = parser
    return parser

def get_cached_parser_for_path(path):
    language = path.suffix[1:]
    if language is None:
        return None
    elif language == "txt":
        # no need to log... just skip txt files
        return None
    elif language == "py":
        language = "python"
    elif language == "sh":
        language = "bash"
    # elif language == "fish":
    #     language = "fish"
    elif language == "lua":
        language = "lua"
    elif language == "js":
        language = "javascript"
    elif language == "ts":
        language = "typescript"
    elif language == "c":
        language = "c"
    elif language == "cpp":
        language = "cpp"
    else:
        logger.warning(f'language not supported for tree_sitter chunker: {language=}')
        return None

    return get_cached_parser(language)

def build_ts_chunks_from_source_bytes(path: Path, file_hash: str, source_bytes: bytes, options: RAGChunkerOptions) -> list[Chunk]:

    # language = get_language('python')

    parser = get_cached_parser_for_path(path)
    if parser is None:
        return []

    with logger.timer(f'parse_ts {path}'):
        tree = parser.parse(source_bytes)

    def get_class_signature(node):
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
            # print(f'  {child.type=}\n    {text=}')
            if child.type == stop_node_type:
                stop_before_node = child
                break

        if not stop_before_node:
            return f"--- unexpected {stop_node_type=} NOT FOUND ---"

        return source_bytes[node.start_byte:stop_before_node.start_byte] \
                .decode("utf-8", errors="replace") \
                .strip()

    def get_function_signature(node):
        sig = None

        stop_before_node = None

        # algorithm: signature == copy everything until start of the function body
        # - function_declaration => statement_block (typescript)
        # - function_definition => block (lua)
        #   function_definition => compound_statement (cpp)
        #   - TODO what others are covered via 'definition' => IIRC that is why I have .find() below
        # PRN strip 2+ lines that are purely comments?

        stop_node_types = []
        if node.type == 'function_declaration':
            stop_node_types = ["statement_block"]
        elif node.type.find("function_definition") >= 0:
            stop_node_types = ["block", "compound_statement"]
        else:
            return f"--- TODO {node.type} ---"

        for child in node.children:
            # text = child.text.decode("utf-8", errors="replace")
            # print(f'  {child.type=}\n    {text=}')
            if child.type in stop_node_types:
                stop_before_node = child
                break

        if not stop_before_node:
            return f"--- unexpected {stop_node_types=} NOT FOUND ---"

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

    def collect_key_nodes(node: Node, collected_parent: bool = False) -> tuple[list[Node], dict[Node, str]]:
        nodes: list[Node] = []
        sigs_by_node: dict[Node, str] = {}

        # TODO should I have a set per language that I keep?
        if node.type == "function_definition" \
            or node.type == "local_function_definition_statement" \
            or node.type == "function_definition_statement" \
            or node.type == "function_declaration":
            # ts: function_declaration
            # lua: function_definition == anonymous functions
            # python: function_definition == named functions
            # lua: named functions (local_function_definition_statement/local vs function_definition_statement/global)
            # FOR lua functions, grab --- triple dash comments before function (until blank line)
            nodes.append(node)
            collected_parent = True
            # TODO track sig with node
            sig = get_function_signature(node)
            if sig is not None:
                sigs_by_node[node] = sig
        elif node.type == "class_definition" \
            or node.type == "class_declaration":
            # typescript class_declaration
            # python
            nodes.append(node)
            collected_parent = True
            sig = get_class_signature(node)
            if sig is not None:
                sigs_by_node[node] = sig
        elif logger.isEnabledForDebug() and not collected_parent:
            debug_uncollected_node(node)
        # else:
        #     print(f"UNMATCHED {node.type}")

        for child in node.children:
            _nodes, _sigs_by_node = collect_key_nodes(child, collected_parent)
            nodes.extend(_nodes)
            sigs_by_node.update(_sigs_by_node)

        return nodes, sigs_by_node

    def debug_uncovered_lines(source_bytes, key_nodes):
        """
        Given a tree-sitter tree and the raw source bytes, print any lines that are not
        covered by any node returned by collect_key_nodes(tree.root_node).
        """

        # Build a set of line numbers that are covered by any node.
        covered = set()
        for node in key_nodes:
            start_line = node.start_point[0]
            end_line = node.end_point[0]  # inclusive
            for ln in range(start_line, end_line + 1):
                covered.add(ln)

        source_lines = source_bytes.splitlines()

        uncovered = [ln for ln in range(len(source_lines)) if ln not in covered]

        if uncovered:
            logger.debug("[bold on red] *********************** Uncovered lines *********************** ")
            last_ln = -1
            for ln in uncovered:
                if ln - last_ln > 1:
                    logger.debug("----")  # divide non-contiguous ranges

                # Show line number (1‑based) and content
                logger.debug(f"{ln+1:4d}: {source_lines[ln].decode('utf-8', errors='replace')}")
                last_ln = ln

        else:
            logger.debug("All lines are covered by key nodes.")

    key_nodes, sigs_by_node = collect_key_nodes(tree.root_node)
    if logger.isEnabledForDebug():
        debug_uncovered_lines(source_bytes, key_nodes)

    # This will list every line that does not fall inside any of the key nodes,
    # which is handy for inspecting stray or unparsed sections of the file.

    chunks = []
    for fn in key_nodes:
        # logger.debug(f'{fn=}')

        start_line_base0 = fn.start_point[0]
        end_line_base0 = fn.end_point[0]
        start_column_base0 = fn.start_point[1]
        end_column_base0 = fn.end_point[1]

        chunk_type = "ts"  # PRN and/or set node type?
        chunk_id = chunk_id_with_columns_for(path, chunk_type, start_line_base0, start_column_base0, end_line_base0, end_column_base0, file_hash)
        text = fn.text.decode('utf-8')
        # TODO logic to split up if over a certain size (tokens)
        # TODO plug in new SIG/FUNC/etc tag header info like in test case

        if sigs_by_node.get(fn) is not None:
            sig = sigs_by_node[fn]
        else:
            sig = ""

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
            signature=sig,
        )

        chunks.append(chunk)

    return chunks
