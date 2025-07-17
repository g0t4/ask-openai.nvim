from dataclasses import dataclass
from pathlib import Path

from pygls.workspace import TextDocument

from .build import build_file_chunks, build_from_lines, get_file_hash, get_file_hash_from_lines
from .logs import get_logger
from .storage import Datasets, load_all_datasets
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

    q_vec = model_wrapper.encode_query(text)
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

        # TODO capture absolute path in indexer! that way I dont have to rebuild absolute path here?
        chunk_file_abs = chunk.file  # capture abs path, already works
        same_file = current_file_abs == chunk_file_abs
        if same_file:
            logger.warning(f"Skip match in same file")
            # PRN could filter too high of similarity instead? or somem other rerank or ?
            continue
        logger.debug(f"matched {chunk.file}:L{chunk.start_line}-{chunk.end_line}")

        @dataclass
        class BaseContextChunk:
            text: str
            file: str
            start_line: int
            end_line: int
            type: str

        @dataclass
        class ContextChunk(BaseContextChunk):
            score: float
            rank: int

        match = ContextChunk(
            text=chunk.text,
            file=chunk.file,
            start_line=chunk.start_line,
            end_line=chunk.end_line,
            type=chunk.type,
            score=float(scores[0][rank]),
            rank=rank + 1,
        )

        matches.add(match)

    if len(matches) == 0:
        # warn if this happens, that all were basically the same doc
        logger.warning(f"No matches found for {current_file_abs=}")

    return matches

def update_file_from_disk(file_path, model_wrapper):
    # FYI right now exists for integration testing as I don't know if I can use document type from pygls in that test (yet?)
    file_path = Path(file_path)

    hash = get_file_hash(file_path)
    with logger.timer(f"build_file_chunks {fs.get_loggable_path(file_path)}"):
        new_chunks = build_file_chunks(file_path, hash)

    datasets.update_file(file_path, new_chunks, model_wrapper)

def update_file_from_pygls_doc(doc: TextDocument, model_wrapper):
    file_path = Path(doc.path)

    lines_hash = get_file_hash_from_lines(doc.lines)

    new_chunks = build_from_lines(file_path, lines_hash, doc.lines)

    with logger.timer(f"update_file {fs.get_loggable_path(file_path)}"):
        datasets.update_file(file_path, new_chunks, model_wrapper)
