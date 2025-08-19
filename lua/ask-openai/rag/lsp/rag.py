from dataclasses import dataclass
from pathlib import Path

from pygls.workspace import TextDocument

from .chunker import build_chunks_from_file, build_line_range_chunks_from_lines, build_ts_chunks_from_file, get_file_hash, get_file_hash_from_lines
from .logs import get_logger
from .storage import Datasets, load_all_datasets
from index.validate import DatasetsValidator
from lsp import fs

logger = get_logger(__name__)

datasets: Datasets

class ContextResult:

    def __init__(self):
        self.matches = []

    def add(self, match):
        self.matches.append(match)

    def __len__(self):
        return len(self.matches)

def load_model_and_indexes(dot_rag_dir: Path, model_wrapper):
    global datasets
    datasets = load_all_datasets(dot_rag_dir)
    model_wrapper.ensure_model_loaded()

def validate_rag_indexes():
    validator = DatasetsValidator(datasets)
    validator.validate()

# PRN make top_k configurable (or other params)
def handle_query(message, model_wrapper, top_k=3):
    text = message.get("text")
    if text is None or len(text) == 0:
        logger.error("[red bold][ERROR] No text provided")
        return {"failed": True, "error": "No text provided"}

    vim_filetype = message.get("vim_filetype")

    current_file_abs = message.get("current_file_absolute_path")
    dataset = datasets.for_file(current_file_abs, vim_filetype=vim_filetype)
    if dataset is None:
        logger.error(f"No dataset")
        return {"failed": True, "error": f"No dataset for {current_file_abs}"}

    logger.pp_debug("[blue bold]RAG[/blue bold] query", message)

    # TODO query more than top 3 and then remove same file matches
    #   stop gap can I just take highest scores for now from embeddings only?
    #   AHH MAN... skip match in same file is dominating results!
    #     can I limit initial query to skip by id of chunks in same file?
    #  PRN later, add RE-RANK!

    instruct = message.get("instruct")

    q_vec = model_wrapper.encode_query(text, instruct)
    # FAISS search (GIL released)
    top_k_padded = top_k * 3
    scores, ids = dataset.index.search(q_vec, top_k_padded)

    logger.pp_debug('scores', scores)
    logger.pp_debug('ids', ids)

    matches = ContextResult()
    for rank, idx in enumerate(ids[0]):
        if len(matches) >= top_k:
            break

        chunk = datasets.get_chunk_by_faiss_id(idx)
        if chunk is None:
            logger.error(f"Missing chunk for id: {idx}")
            continue

        score = scores[0][rank]
        logger.pp_debug(f"chunk {score}", chunk)

        # PRN capture absolute path in indexer! that way I dont have to rebuild absolute path here?
        chunk_file_abs = chunk.file  # capture abs path, already works
        same_file = current_file_abs == chunk_file_abs
        if same_file:
            logger.warning(f"Skip match in same file")
            continue
        logger.debug(f"matched {chunk.file}:L{chunk.start_line}-{chunk.end_line}")

        @dataclass
        class BaseContextChunk:
            text: str
            file: str
            start_line: int
            start_column: int
            end_line: int
            end_column: int | None
            type: str

        @dataclass
        class ContextChunk(BaseContextChunk):
            score: float
            rank: int

        match = ContextChunk(
            text=chunk.text,
            file=chunk.file,
            start_line=chunk.start_line,
            start_column=chunk.start_column,
            end_line=chunk.end_line,
            end_column=chunk.end_column,
            type=chunk.type,
            score=float(scores[0][rank]),
            rank=rank + 1,
        )

        matches.add(match)

    if len(matches) == 0:
        # TODO go back and query next X?
        # warn if this happens, that all were basically the same doc
        logger.warning(f"No matches found for {current_file_abs=}")

    return matches

def update_file_from_pygls_doc(lsp_doc: TextDocument, model_wrapper, enable_ts_chunks):
    file_path = Path(lsp_doc.path)

    hash = get_file_hash_from_lines(lsp_doc.lines)

    # TODO merge this lines and/or ts chunking logic into the chunker
    new_chunks = build_line_range_chunks_from_lines(file_path, hash, lsp_doc.lines)
    if enable_ts_chunks:
        # TODO add indexer test that includes ts chunking (maybe even disable line range chunking)
        source_bytes = ''.join(lsp_doc.lines).encode(encoding='utf-8')
        ts_chunks = build_ts_chunks_from_file(file_path, hash)
        new_chunks.extend(ts_chunks)

    with logger.timer(f"update_file {fs.get_loggable_path(file_path)}"):
        datasets.update_file(file_path, new_chunks, model_wrapper)
