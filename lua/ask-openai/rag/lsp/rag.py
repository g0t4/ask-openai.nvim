from dataclasses import dataclass
from pathlib import Path

from pygls.workspace import TextDocument

from lsp.chunker import build_chunks_from_lines, get_file_hash_from_lines, RAGChunkerOptions
from lsp.logs import get_logger
from lsp.storage import Datasets, load_all_datasets
from lsp.remote.retrieval import *
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
def handle_query(message, model_wrapper, top_k=3, skip_same_file=False):

    # * validate fields
    text = message.get("text")
    if text is None or len(text) == 0:
        logger.error("[red bold][ERROR] No text provided")
        return {"failed": True, "error": "No text provided"}
    vim_filetype = message.get("vim_filetype")
    current_file_abs = message.get("current_file_absolute_path")

    # * load dataset
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

    query_vector = model_wrapper.encode_query(text, instruct)
    if skip_same_file:
        # grab 3x the docs so you can skip same file matches
        top_k_padded = top_k * 3
    else:
        top_k_padded = top_k
    scores, ids = dataset.index.search(query_vector, top_k_padded)

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
        is_same_file = current_file_abs == chunk_file_abs
        if skip_same_file and is_same_file:
            logger.warning(f"Skip match in same file")
            continue
        logger.debug(f"matched {chunk.file}:base0-L{chunk.base0.start_line}-{chunk.base0.end_line}")

        match = LSPRankedMatch(
            text=chunk.text,
            file=chunk.file,
            start_line_base0=chunk.base0.start_line,
            start_column_base0=chunk.base0.start_column,
            end_line_base0=chunk.base0.end_line,
            end_column_base0=chunk.base0.end_column,
            type=chunk.type,
            signature=chunk.signature,
            embed_score=float(scores[0][rank]),
            embed_rank=rank + 1,
        )

        matches.add(match)

    if len(matches) == 0:
        # TODO go back and query next X?
        # warn if this happens, that all were basically the same doc
        logger.warning(f"No matches found for {current_file_abs=}")

    return matches

def update_file_from_pygls_doc(lsp_doc: TextDocument, model_wrapper, options: RAGChunkerOptions):
    file_path = Path(lsp_doc.path)

    hash = get_file_hash_from_lines(lsp_doc.lines)

    new_chunks = build_chunks_from_lines(file_path, hash, lsp_doc.lines, options)

    with logger.timer(f"update_file {fs.get_loggable_path(file_path)}"):
        datasets.update_file(file_path, new_chunks, model_wrapper)
