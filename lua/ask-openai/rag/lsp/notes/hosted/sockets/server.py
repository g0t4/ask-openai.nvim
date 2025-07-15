import socket
import signal
import struct
import msgpack

from lsp.notes import transformers_qwen3
from lsp.logs import get_logger, logging_fwk_to_console
from lsp.notes.hosted.sockets.comms import *

# logging_fwk_to_console("WARN")
logging_fwk_to_console("INFO")
# logging_fwk_to_console("DEBUG")
logger = get_logger(__name__)
# TODO measure all logging/prints and remove/threshold any that are unacceptable (i.e. > 10ms?)

def encode(texts: list[str]):
    # logger.debug(texts)
    vec = transformers_qwen3.encode(texts)
    vec_list = vec.cpu().numpy().tolist()
    # logger.debug(vec_list)
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

while True:
    conn, _ = server.accept()

    rx_msg = recv_len_then_msg(conn)
    if not rx_msg:
        conn.close()
        continue

    rx_text = rx_msg['texts']

    embedding = encode(rx_text)

    tx_msg = {'embedding': embedding}
    send_len_then_msg(conn, tx_msg)
    conn.close()
