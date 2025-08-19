import hashlib
from pathlib import Path
from tree_sitter import Node
from tree_sitter_languages import get_language, get_parser

from lsp.storage import Chunk, FileStat, chunk_id_for, chunk_id_to_faiss_id, chunk_id_with_columns_for
from lsp.logs import get_logger

logger = get_logger(__name__)

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

def build_file_chunks(path: Path | str, file_hash: str) -> list[Chunk]:
    path = Path(path)

    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        # each line has trailing newline (it is not stripped out)
        lines = f.readlines()
        return build_from_lines(path, file_hash, lines)

def build_from_lines(path: Path, file_hash: str, lines: list[str]) -> list[Chunk]:

    # when the time comes, figure out how to alter these:
    lines_per_chunk = 20
    overlap = 5

    def iter_chunks(lines, min_chunk_size=10):
        n_lines = len(lines)
        step = lines_per_chunk - overlap
        for idx, i in enumerate(range(0, n_lines, step)):
            start = i
            end_line = min(i + lines_per_chunk, n_lines)
            if (end_line - start) < min_chunk_size and idx > 0:
                break

            chunk_type = "lines"
            start_line = start + 1
            chunk_id = chunk_id_for(path, chunk_type, start_line, end_line, file_hash)
            yield Chunk(
                id=chunk_id,
                id_int=str(chunk_id_to_faiss_id(chunk_id)),
                text="".join(lines[start:end_line]),
                file=str(path),
                start_line=start_line,
                start_column=0,  # always the first column for line ranges
                end_line=end_line,
                end_column=None,
                type=chunk_type,
                file_hash=file_hash,
            )

    chunks = []
    for _, chunk in enumerate(iter_chunks(lines)):
        chunks.append(chunk)

    return chunks

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
    else:
        logger.warning(f'language not supported for tree_sitter chunker: {language=}')
        return None

    return get_cached_parser(language)

def build_ts_chunks(path: Path, file_hash: str) -> list[Chunk]:
    """
    Build chunks from a Python file using tree‑sitter.
    Each chunk corresponds to a top‑level function definition.
    """

    # language = get_language('python')

    parser = get_cached_parser_for_path(path)
    if parser is None:
        return []

    with open(path, 'rb') as file:
        # TODO don't reload file, load once with build_file_chunks
        source = file.read()

    with logger.timer('parse_ts ' + str(path)):
        tree = parser.parse(source)

    def collect_key_nodes(node: Node) -> list[Node]:
        nodes: list[Node] = []
        if node.type == "function_definition":
            nodes.append(node)
        if node.type == "class_definition":
            nodes.append(node)

        for child in node.children:
            nodes.extend(collect_key_nodes(child))
        return nodes

    nodes = collect_key_nodes(tree.root_node)

    chunks = []
    for fn in nodes:
        # print(f'{fn=}')

        start_line = fn.start_point[0]
        end_line = fn.end_point[0]
        start_column = fn.start_point[1]
        end_column = fn.end_point[1]

        chunk_type = "ts"  # PRN and/or set node type?
        chunk_id = chunk_id_with_columns_for(path, chunk_type, start_line, start_column, end_line, end_column, file_hash)
        text = fn.text.decode('utf-8')
        # TODO logic to split up if over a certain size (tokens)
        # TODO plug in new SIG/FUNC/etc tag header info like in test case
        chunk = Chunk(
            id=chunk_id,
            id_int=str(chunk_id_to_faiss_id(chunk_id)),
            text=text,
            file=str(path),
            start_line=start_line,
            start_column=start_column,
            end_line=end_line,
            end_column=end_column,
            type=chunk_type,
            file_hash=file_hash,
        )

        chunks.append(chunk)

    return chunks
