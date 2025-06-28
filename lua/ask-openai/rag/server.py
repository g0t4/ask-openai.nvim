import json
import json
import socket

import faiss
from rich import print
from sentence_transformers import SentenceTransformer

# this is simple and to the point...
#  can reload data after this alone proves itself!
#  for now restart this server!
#
index_path = "./tmp/rag_index/vectors.index"
chunks_path = "./tmp/rag_index/chunks.json"

index = faiss.read_index(index_path)
with open(chunks_path) as f:
    chunks = json.load(f)
model_name = "intfloat/e5-base-v2"
model = SentenceTransformer(model_name)

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.bind("/tmp/raggy.sock")
sock.listen(1)

def handle_query(data):
    # return embedding for the string
    return {"embedding": [0.1, 0.2, 0.3]}

while True:
    conn, _ = sock.accept()
    data = conn.recv(4096).decode()
    print(f"Received query {data}")
    query = json.loads(data)
    result = handle_query(query["text"])
    conn.send(json.dumps(result).encode())
    conn.close()
