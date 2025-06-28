from contextlib import contextmanager
import json
import os
import socket

import faiss
from rich import print

from timing import Timer

# FYI:
#   test with:
# cdr # repo root for tmp dir
# python3 lua/ask-openai/rag/server.py
#   TODO make into package if this works out with FIM
# echo '{"text": "server sent events"}' | socat - UNIX-CONNECT:./tmp/raggy.sock | jq



with Timer("importing sentence_transformers"):
    from sentence_transformers import SentenceTransformer

# this is simple and to the point...
#  can reload data after this alone proves itself!
#  for now restart this server!
#
index_path = "./tmp/rag_index/vectors.index"
chunks_path = "./tmp/rag_index/chunks.json"

with Timer("Loading index and chunks"):
    index = faiss.read_index(index_path)
    print(f"[INFO] Loaded index {index_path} with {index.ntotal} vectors")

with Timer("Loading chunks"):
    with open(chunks_path) as f:
        chunks = json.load(f)
    print(f"[INFO] Loaded {len(chunks)} chunks from {chunks_path}")

model_name = "intfloat/e5-base-v2"
model = SentenceTransformer(model_name)
print(f"[INFO] Loaded model {model_name}")
print("[bold green]READY")
print()

# PRN make top_k configurable (or other params)
def handle_query(query, top_k=3):

    # query: prefix is what the model was trained on (and the documents have passage: prefix)
    q_vec = model.encode([f"query: {query}"], normalize_embeddings=True)\
        .astype("float32")
    scores, ids = index.search(q_vec, top_k)

    matches = []
    for rank, idx in enumerate(ids[0]):
        chunk = chunks[idx]
        matches.append({"score": float(scores[0][rank]), "text": chunk["text"], "file": chunk.get("file"), "start_line": chunk.get("start_line"), "end_line": chunk.get("end_line"), "type": chunk.get("type"), "rank": rank + 1})

    return {"matches": matches}

@contextmanager
def unix_socket_server(path):
    if os.path.exists(path):
        os.remove(path)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path)
    server.listen(1)
    try:
        yield server
    finally:
        server.close()
        os.remove(path)

@contextmanager
def accept_client(server):
    conn, _ = server.accept()
    try:
        yield conn
    finally:
        conn.close()

with unix_socket_server("./tmp/raggy.sock") as server:
    while True:
        with accept_client(server) as conn:
            data = conn.recv(8192).decode()
            if not data:
                print("[INFO] No data received, skipping...")
                continue
            print(f"[INFO] Received data: {data}")

            # TODO failures
            query = json.loads(data)

            matches = handle_query(query["text"])
            conn.send(json.dumps(matches).encode())
