import socket
import signal
import struct
import msgpack
from transformers import AutoModel, AutoTokenizer
import torch

from lsp.notes import transformers_qwen3

def encode(texts: list[str]):
    # print(f"encode w/ {type(transformers_qwen3.model)}")
    print(texts)
    vec = transformers_qwen3.encode(texts)
    vec_list = vec.cpu().numpy().tolist()
    print(vec_list)
    return vec_list

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

def recv_exact(sock, size):
    buf = b''
    while len(buf) < size:
        chunk = sock.recv(size - len(buf))
        if not chunk:
            raise ConnectionError("Socket connection closed")
        buf += chunk
    return buf

while True:
    conn, _ = server.accept()

    print("receiving...")
    rx_msg_len_packed = recv_exact(conn, 4)
    print(f'{rx_msg_len_packed=}')
    rx_msg_len = struct.unpack('!I', rx_msg_len_packed)[0]
    print(f'{rx_msg_len=}')
    if not rx_msg_len:
        # PRN what checks?
        conn.close()
        continue
    rx_msg_packed = recv_exact(conn, rx_msg_len)

    rx_msg = msgpack.unpackb(rx_msg_packed, raw=False)
    rx_text = rx_msg['texts']
    print()

    embedding = encode(rx_text)

    print("transmitting...")
    tx_msg = {'embedding': embedding}
    tx_msg_packed = msgpack.packb(tx_msg, use_bin_type=True)
    tx_msg_len = len(tx_msg_packed)
    print(f'{tx_msg_len=}')
    tx_msg_len_packed = struct.pack('!I', tx_msg_len)  # 4-byte network byte order
    print(f'{tx_msg_len_packed=}')
    conn.sendall(tx_msg_len_packed + tx_msg_packed)
    conn.close()
