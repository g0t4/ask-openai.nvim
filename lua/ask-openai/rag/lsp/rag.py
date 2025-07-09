import os
from pathlib import Path
from typing import List

import faiss
import rich.pretty

from .logs import LogTimer, logging
from .storage import Chunk, chunk_id_to_faiss_id, load_chunks

# avoid checking for model files every time you load the model...
#   550ms load time vs 1200ms for =>    model = SentenceTransformer(model_name)
os.environ["TRANSFORMERS_OFFLINE"] = "1"

logger = logging.getLogger(__name__)

def log_pretty(message, data):
    logger.info(f"{message} {rich.pretty.pretty_repr(data)}")

chunks_by_faiss_id: dict[int, Chunk] = {}

def load_model_and_indexes(root_fs_path: Path):
    global model, index, chunks_by_faiss_id
    from .model import model

    # index_path = "../../../tmp/rag_index/lua/vectors.index"
    # chunks_path = "../../../tmp/rag_index/lua/chunks.json"
    lua_dir = root_fs_path / ".rag" / "lua"
    index_path_str = str(lua_dir / "vectors.index")
    chunks_path = lua_dir / "chunks.json"

    with LogTimer("Loading index and chunks"):
        index = faiss.read_index(index_path_str)
        logger.info(f"Loaded index {index_path_str} with {index.ntotal} vectors")

    with LogTimer("Loading chunks"):
        chunks_by_file_typed = load_chunks(chunks_path)

    chunks_by_faiss_id = {}
    for _, chunks in chunks_by_file_typed.items():
        for chunk in chunks:
            faiss_id = chunk_id_to_faiss_id(chunk.id)
            chunks_by_faiss_id[faiss_id] = chunk

    # log_pretty("chunks_by_faiss_id", chunks_by_faiss_id)
    logger.info(f"Loaded {len(chunks_by_faiss_id)} chunks by id")

# PRN make top_k configurable (or other params)
def handle_query(message, top_k=3):
    if model is None:
        logger.info("MISSING MODEL, CANNOT query it")
        return

    text = message.get("text")
    if not text:
        logger.info("[red bold][ERROR] No query provided")
        return {"failed": True, "error": "No query provided"}
    # TODO does this semantic belong here? or should it be like exclude_files?
    #   can worry about this when I expand RAG beyond FIM
    current_file_absolute_path = message.get("current_file_absolute_path")
    # logger.info(f"Querying for [green bold]{text}[/green bold]")
    # logger.info(f"Current file: [green bold]{current_file_absolute_path}[/green bold]")

    # query: prefix is what the model was trained on (and the documents have passage: prefix)
    q_vec = model.encode([f"query: {text}"], normalize_embeddings=True).astype("float32")
    # FAISS search (GIL released)
    scores, ids = index.search(q_vec, top_k)
    # logger.info(f'{scores=}')
    # logger.info(f'{ids=}')

    matches = []
    for rank, idx in enumerate(ids[0]):
        chunk = chunks_by_faiss_id[idx]
        # TODO graceful handling of missing chunk? (i.e. change indexing ID  :) )
        # TODO! capture absolute path in indexer! that way I dont have to rebuild absolute path here?
        chunk_file_abs = chunk.file  # capture abs path, already works
        same_file = current_file_absolute_path == chunk_file_abs
        logger.info(f"{current_file_absolute_path=} {chunk_file_abs=} {chunk.file=} {same_file=}")
        if same_file:
            logger.warning(f"Skipping match in current file: {chunk_file_abs=}")
            # PRN could filter too high of similarity instead? or somem other rerank or ?
            continue
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
        logger.warning("No matches found")

    return {"matches": matches}
