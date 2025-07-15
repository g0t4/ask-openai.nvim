import socket
import msgpack
from transformers import AutoModel, AutoTokenizer
import torch

MODEL_NAME = "intfloat/e5-base-v2"

tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
model = AutoModel.from_pretrained(MODEL_NAME).eval()

def encode(text):
    inputs = tokenizer(text, return_tensors="pt", padding=True, truncation=True)
    with torch.no_grad():
        embeddings = model(**inputs).last_hidden_state.mean(dim=1)
    return embeddings[0].tolist()

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind("/tmp/embed.sock")
server.listen()

while True:
    conn, _ = server.accept()
    data = conn.recv(4096)
    if not data:
        conn.close()
        continue

    text = msgpack.unpackb(data, raw=False)['text']
    embedding = encode(text)

    packed = msgpack.packb({'embedding': embedding}, use_bin_type=True)
    conn.sendall(packed)
    conn.close()

