import json
import os
from pathlib import Path

import faiss

from .ids import chunk_id_to_faiss_id
from .logs import LogTimer, logging

# avoid checking for model files every time you load the model...
#   550ms load time vs 1200ms for =>    model = SentenceTransformer(model_name)
os.environ["TRANSFORMERS_OFFLINE"] = "1"

def load_model_and_indexes(root_fs_path: Path):
    global model, index, chunks_by_faiss_id
    from .model import model

    # index_path = "../../../tmp/rag_index/lua/vectors.index"
    # chunks_path = "../../../tmp/rag_index/lua/chunks.json"
    lua_dir = root_fs_path / ".rag" / "lua"
    index_path = str(lua_dir / "vectors.index")
    chunks_path = str(lua_dir / "chunks.json")

    with LogTimer("Loading index and chunks"):
        index = faiss.read_index(index_path)
        logging.info(f"Loaded index {index_path} with {index.ntotal} vectors")

    with LogTimer("Loading chunks"):
        with open(chunks_path) as f:
            chunks = json.load(f)
        # logging.info(f"Loaded {len(chunks)} chunks from {chunks_path}")

    chunks_by_faiss_id = {}
    # TODO! update for storage format change...  now chunks.json is object with file paths as keys, and each has array of its chunks
    # FYI STILL USING LAST BUILD => when rebuild index then need to update this code
    #  chunks will be dict[key:string, list[chunk]]
    #
    #  # this is new code, should work fine: (get rid of loop below)
    #   and rename chunks above to chunks_by_file
    #
    # for file in chunks_by_file:
    #     for chunk in chunks_by_file[file]:
    #         chunk['faiss_id'] = chunk_id_to_faiss_id(chunk['id'])
    #         # logging.info(f"{chunk['faiss_id']=}")
    #         chunks_by_faiss_id[chunk['faiss_id']] = chunk

    for chunk in chunks:
        chunk['faiss_id'] = chunk_id_to_faiss_id(chunk['id'])
        # logging.info(f"{chunk['faiss_id']=}")
        chunks_by_faiss_id[chunk['faiss_id']] = chunk
    logging.info(f"Loaded {chunks_by_faiss_id=}")
    logging.info(f"Loaded {len(chunks_by_faiss_id)} chunks by id")


# PRN make top_k configurable (or other params)
def handle_query(message, top_k=3):
    if model is None:
        logging.info("MISSING MODEL, CANNOT query it")
        return

    text = message.get("text")
    if not text:
        logging.info("[red bold][ERROR] No query provided")
        return {"failed": True, "error": "No query provided"}
    # TODO does this semantic belong here? or should it be like exclude_files?
    #   can worry about this when I expand RAG beyond FIM
    current_file_absolute_path = message.get("current_file_absolute_path")
    # logging.info(f"Querying for [green bold]{text}[/green bold]")
    # logging.info(f"Current file: [green bold]{current_file_absolute_path}[/green bold]")

    # query: prefix is what the model was trained on (and the documents have passage: prefix)
    q_vec = model.encode([f"query: {text}"], normalize_embeddings=True).astype("float32")
    # FAISS search (GIL released)
    scores, ids = index.search(q_vec, top_k)
    # logging.info(f'{scores=}')
    # logging.info(f'{ids=}')

    matches = []
    for rank, idx in enumerate(ids[0]):
        chunk = chunks_by_faiss_id[idx]
        # TODO graceful handling of missing chunk? (i.e. change indexing ID  :) )
        # TODO! capture absolute path in indexer! that way I dont have to rebuild absolute path here?
        chunk_file_abs = chunk["file"] # capture abs path, already works
        same_file = current_file_absolute_path == chunk_file_abs
        logging.info(f"{current_file_absolute_path=} {chunk_file_abs=} {chunk["file"]=} {same_file=}")
        if same_file:
            logging.warning(f"Skipping match in current file: {chunk_file_abs=}")
            # PRN could filter too high of similarity instead? or somem other rerank or ?
            continue
        matches.append({
            "score": float(scores[0][rank]),
            "text": chunk["text"],
            "file": chunk.get("file"),
            "start_line": chunk.get("start_line"),
            "end_line": chunk.get("end_line"),
            "type": chunk.get("type"),
            "rank": rank + 1,
        })
    if len(matches) == 0:
        # warn if this happens, that all were basically the same doc
        logging.warning("No matches found")

    return {"matches": matches}
