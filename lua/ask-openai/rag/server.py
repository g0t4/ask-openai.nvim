import asyncio
import json
import signal

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
with Timer(f"Loading SentenceTransformer model ({model_name})"):
    model = SentenceTransformer(model_name)

# PRN make top_k configurable (or other params)
def handle_query(message, top_k=3):
    text = message.get("text")
    if not text:
        print("[red bold][ERROR] No query provided")
        return {"failed": True, "error": "No query provided"}
    # TODO does this semantic belong here? or should it be like exclude_files?
    #   can worry about this when I expand RAG beyond FIM
    current_file = message.get("current_file")
    # print(f"[INFO] Querying for [green bold]{text}[/green bold]")
    # print(f"[INFO] Current file: [green bold]{current_file}[/green bold]")

    # query: prefix is what the model was trained on (and the documents have passage: prefix)
    q_vec = model.encode([f"query: {text}"], normalize_embeddings=True)\
        .astype("float32")
    # TODO how do I exclude matches in the same file? need to pass file to exclude but then also not query those chunks? do I get top 10 and then take first 3 not the same file?
    # FAISS search (GIL released)
    scores, ids = index.search(q_vec, top_k)

    matches = []
    for rank, idx in enumerate(ids[0]):
        chunk = chunks[idx]
        if current_file and current_file == chunks[idx]["file"]:
            print("[yellow bold][WARN] Skipping match in current file", current_file)
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
        print("[red bold][WARN] No matches found")

    return {"matches": matches}

async def handle_client(reader, writer):
    data = await reader.read(4096)
    if not data:
        print("[red bold][WARN] No data received, skipping...")
        return

    # print(f"[INFO] Received data: {data}")

    async def send_message(message):
        writer.write(json.dumps(message).encode())
        await writer.drain()
        writer.close()
        await writer.wait_closed()

    with Timer("Query"):
        try:
            query = json.loads(data)
        except json.JSONDecodeError:
            print(f"[red bold][ERROR] Failed to parse JSON: {data}")
            await send_message({"failed": True, "error": "Invalid JSON"})
            return

        response = handle_query(query)
        await send_message(response)

async def start_socket_server(stop_event: asyncio.Event):
    server = await asyncio.start_server(handle_client, 'localhost', 9999)
    print("[bold green]READY\n")

    async with server:
        await stop_event.wait()
        print("[INFO] Shutting down...")
        server.close()
        await server.wait_closed()

def main():
    stop_event = asyncio.Event()

    def shutdown():
        print("\n[INFO] Received shutdown signal")
        stop_event.set()

    loop = asyncio.get_event_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, shutdown)

    loop.run_until_complete(start_socket_server(stop_event))

if __name__ == '__main__':
    main()
