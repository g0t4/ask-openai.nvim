import asyncio
import json

import faiss
from rich import print

from timing import Timer

# FYI:
#   test with:
# cdr # repo root for tmp dir
# python3 lua/ask-openai/rag/server.py
# echo '{"text": "server sent events"}' | socat - TCP:localhost:9999 | jq
#
# older unix socket:
# echo '{"text": "server sent events"}' | socat - UNIX-CONNECT:./tmp/raggy.sock | jq

# TODO! try Alibaba-NLP/gte-base-en-v1.5 ...  for the embeddings model

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
    # TODO how do I exclude matches in the same file? need to pass file to exclude but then also not query those chunks? do I get top 10 and then take first 3 not the same file?
    # FAISS search (GIL released)
    scores, ids = index.search(q_vec, top_k)

    matches = []
    for rank, idx in enumerate(ids[0]):
        chunk = chunks[idx]
        matches.append({"score": float(scores[0][rank]), "text": chunk["text"], "file": chunk.get("file"), "start_line": chunk.get("start_line"), "end_line": chunk.get("end_line"), "type": chunk.get("type"), "rank": rank + 1})

    return {"matches": matches}

async def handle_client(reader, writer):
    data = await reader.read(4096)
    if not data:
        print("[red bold][WARN] No data received, skipping...")
        return

    # print(f"[INFO] Received data: {data}")

    # TODO failures
    query = json.loads(data)

    matches = handle_query(query["text"])
    writer.write(json.dumps(matches).encode())

    await writer.drain()
    writer.close()
    await writer.wait_closed()

async def start_socket_server():
    server = await asyncio.start_server(handle_client, 'localhost', 9999)
    async with server:
        await server.serve_forever()

def main():
    asyncio.run(start_socket_server())

if __name__ == '__main__':
    main()
