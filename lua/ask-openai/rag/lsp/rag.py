import os
from pathlib import Path

from .build import build_file_chunks, get_file_hash
from .logs import get_logger
from .storage import Chunk, Datasets, load_all_datasets

# avoid checking for model files every time you load the model...
#   550ms load time vs 1200ms for =>    model = SentenceTransformer(model_name)
os.environ["TRANSFORMERS_OFFLINE"] = "1"

logger = get_logger(__name__)

datasets: Datasets

def load_model_and_indexes(root_fs_path: Path):
    global model, datasets
    from .model import model
    datasets = load_all_datasets(root_fs_path / ".rag")

# PRN make top_k configurable (or other params)
def handle_query(message, top_k=3):
    if model is None:
        logger.info("MISSING MODEL, CANNOT query it")
        return

    text = message.get("text")  # PRN rename to query? instead of text?
    if text is None or len(text) == 0:
        logger.info("[red bold][ERROR] No query text provided")
        return {"failed": True, "error": "No query text provided"}

    current_file_abs = message.get("current_file_absolute_path")
    dataset = datasets.for_file(current_file_abs)
    if dataset is None:
        logger.info(f"No dataset")
        return {"failed": True, "error": f"No dataset for {current_file_abs}"}

    logger.pp_info("[blue bold]RAG[/blue bold] query", message)

    # query: prefix is what the model was trained on (and the documents have passage: prefix)
    # PRN make model wrapper and have it encode both query and passage/document (that was it is model specific, too)
    q_vec = model.encode([f"query: {text}"], normalize_embeddings=True).astype("float32")
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

def update_one_file_from_disk(file_path: str):

    dataset = datasets.for_file(file_path)
    if dataset is None:
        logger.info(f"No dataset for path: {file_path}")
        return

    if file_path not in dataset.chunks_by_file:
        logger.info(f"No chunks for {file_path}")
        # TODO BUILD NEW?
        return

    prior_chunks = dataset.chunks_by_file[file_path]
    if not prior_chunks:
        logger.info(f"Nothing to update for {file_path}")
        # TODO BUILD NEW?
        return

    logger.info(f"Updating {file_path}")
    logger.pp_info("prior_chunks", prior_chunks)

    # TODO! use server.workspace.get_document instead of reading file from disk?
    # document = server.workspace.get_document(params.text_document.uri)
    # current_line = document.lines[params.position.line].strip()

    hash = get_file_hash(file_path)
    new_chunks = build_file_chunks(file_path, hash)
    logger.pp_info("new_chunks", new_chunks)

    # TODO add something to Datasets/RAGDataset to have it handle the update
    #  infact should this function exist elsewhere at some point?
    # dataset.chunks_by_file[path] = new_chunks
