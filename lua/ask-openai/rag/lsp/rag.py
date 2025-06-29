import json
import os

import faiss

from logs import LogTimer, logging
from pathlib import Path
from ids import chunk_id_to_faiss_id

# avoid checking for model files every time you load the model...
#   550ms load time vs 1200ms for =>    model = SentenceTransformer(model_name)
os.environ["TRANSFORMERS_OFFLINE"] = "1"

def load_model():
    global model, index, chunks, chunks_by_faiss_id
    with LogTimer("importing sentence_transformers"):
        from sentence_transformers import SentenceTransformer

    index_path = "./tmp/rag_index/lua/vectors.index"
    chunks_path = "./tmp/rag_index/lua/chunks.json"

    with LogTimer("Loading index and chunks"):
        index = faiss.read_index(index_path)
        logging.info(f"[INFO] Loaded index {index_path} with {index.ntotal} vectors")

    with LogTimer("Loading chunks"):
        with open(chunks_path) as f:
            chunks = json.load(f)
        logging.info(f"[INFO] Loaded {len(chunks)} chunks from {chunks_path}")

    chunks_by_faiss_id = {}
    for chunk in chunks:
        chunk['faiss_id'] = chunk_id_to_faiss_id(chunk['id'])
        logging.info(f"{chunk['faiss_id']=}")
        chunks_by_faiss_id[chunk['faiss_id']] = chunk
    logging.info(f"[INFO] Loaded {len(chunks_by_faiss_id)} chunks by id")

    # TODO try Alibaba-NLP/gte-base-en-v1.5 ...  for the embeddings model
    model_name = "intfloat/e5-base-v2"
    with LogTimer(f"Loading SentenceTransformer model ({model_name})"):
        model = SentenceTransformer(model_name)

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
    current_file = message.get("current_file")
    # logging.info(f"[INFO] Querying for [green bold]{text}[/green bold]")
    # logging.info(f"[INFO] Current file: [green bold]{current_file}[/green bold]")

    # query: prefix is what the model was trained on (and the documents have passage: prefix)
    q_vec = model.encode([f"query: {text}"], normalize_embeddings=True).astype("float32")
    # FAISS search (GIL released)
    scores, ids = index.search(q_vec, top_k)
    logging.info(f'{scores=}')
    logging.info(f'{ids=}')

    matches = []
    current_file_abs = None
    if current_file:
        current_file_abs = Path(current_file).absolute()
    for rank, idx in enumerate(ids[0]):
        chunk = chunks_by_faiss_id[idx]
        chunk_file_abs = Path(chunk["file"]).absolute()
        same_file = current_file_abs == chunk_file_abs
        # logging.info(f"{current_file_abs=} {chunk_file_abs=} {same_file=}")
        if same_file:
            logging.info("[yellow bold][WARN] Skipping match in current file", current_file)
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
        logging.info("[red bold][WARN] No matches found")

    return {"matches": matches}
