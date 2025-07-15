import socket
import signal
import msgpack
from transformers import AutoModel, AutoTokenizer
import torch

from lsp.notes import transformers_qwen3

def encode(texts: list[str]):
    print(f"encode w/ {type(transformers_qwen3.model)}")
    print(texts)
    vec = transformers_qwen3.encode(texts)
    return vec.cpu().numpy().tolist()

# time python3 -m lsp.notes.hosted.sockets.server

# MODEL_NAME = "intfloat/e5-base-v2"
#
# tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
# model = AutoModel.from_pretrained(MODEL_NAME).eval()
#
# def encode(text):
#     inputs = tokenizer(text, return_tensors="pt", padding=True, truncation=True)
#     with torch.no_grad():
#         embeddings = model(**inputs).last_hidden_state.mean(dim=1)
#     return embeddings[0].tolist()

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.bind(("0.0.0.0", 8015))
server.listen()

def signal_handler(sig, frame):
    print('You pressed Ctrl+C!')
    server.close()
    exit(0)

signal.signal(signal.SIGINT, signal_handler)

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
