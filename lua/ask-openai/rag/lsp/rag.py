import os
from pathlib import Path

from pygls.workspace import TextDocument

from .build import build_file_chunks, build_from_lines, get_file_hash, get_file_hash_from_lines
from .logs import get_logger
from .storage import Chunk, Datasets, load_all_datasets
from .model import model_wrapper

logger = get_logger(__name__)

datasets: Datasets

def load_model_and_indexes(dot_rag_dir: Path):
    global datasets
    # PRN add a dataset_wrapper like model_wrapper and let it handle lazy load and be reusable across entire process (any imports are both lazy loaded and still singleton)
    datasets = load_all_datasets(dot_rag_dir)
    model_wrapper.ensure_model_loaded()  # now I want to trigger the eager load, not at module import time but when I am ready here

# PRN make top_k configurable (or other params)
def handle_query(message, top_k=3):

    text = message.get("text")
    if text is None or len(text) == 0:
        logger.info("[red bold][ERROR] No text provided")
        return {"failed": True, "error": "No text provided"}

    current_file_abs = message.get("current_file_absolute_path")
    dataset = datasets.for_file(current_file_abs)
    if dataset is None:
        logger.info(f"No dataset")
        return {"failed": True, "error": f"No dataset for {current_file_abs}"}

    logger.pp_info("[blue bold]RAG[/blue bold] query", message)

    # TODO rename model_wrapper back to just model when done inserting it into all usages
    q_vec = model_wrapper.encode_query(text)
    # FAISS search (GIL released)
    scores, ids = dataset.index.search(q_vec, top_k)
    # logger.info(f'{scores=}')
    # logger.info(f'{ids=}')

    matches = []
    for rank, idx in enumerate(ids[0]):
        chunk = datasets.get_chunk_by_faiss_id(idx)
        if chunk is None:
            logger.error(f"Missing chunk for id: {idx}")
            continue

        # TODO capture absolute path in indexer! that way I dont have to rebuild absolute path here?
        chunk_file_abs = chunk.file  # capture abs path, already works
        same_file = current_file_abs == chunk_file_abs
        if same_file:
            logger.warning(f"Skip match in same file")
            # PRN could filter too high of similarity instead? or somem other rerank or ?
            continue
        logger.info(f"matched {chunk.file}:L{chunk.start_line}-{chunk.end_line}")

        matches.append({
            "score": float(scores[0][rank]),
            "text": chunk.text,
            "file": chunk.file,
            "start_line": chunk.start_line,
            "end_line": chunk.end_line,
            "type": chunk.type,
            "rank": rank + 1,
        })
    if len(matches) == 0:
        # warn if this happens, that all were basically the same doc
        logger.warning(f"No matches found for {current_file_abs=}")

    return {"matches": matches}

def update_one_file_from_disk(doc: TextDocument):
    file_path = Path(doc.path)

    # * read directly from disk (update_one_file_from_disk)
    # PRN add a separate overload to read from disk if that is useful in another scenario
    # hash = get_file_hash(file_path)
    # new_chunks = build_file_chunks(file_path, lines_hash)

    # * use pygls workspace docs
    lines_hash = get_file_hash_from_lines(doc.lines)
    new_chunks = build_from_lines(file_path, lines_hash, doc.lines)

    logger.pp_info("new_chunks", new_chunks)

    datasets.update_file(file_path, new_chunks)
