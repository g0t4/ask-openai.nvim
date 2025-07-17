import socket
import signal
import rich

from lsp.notes.hosted.sockets import qwen3
from lsp.logs import get_logger, logging_fwk_to_console
from lsp.notes.hosted.sockets.comms import *

logging_fwk_to_console("WARN")
# logging_fwk_to_console("INFO")
# logging_fwk_to_console("DEBUG")
logger = get_logger(__name__)

def encode(texts: list[str]):
    # logger.debug(texts)
    vec = qwen3.encode(texts)
    logger.debug(vec)
    return vec.tolist()

# z rag
# time python3 -m lsp.notes.hosted.sockets.server

qwen3.test_known_embeddings()

print()
rich.print("[green bold]SERVER READY")

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

    tx_msg = {'embeddings': embedding}
    send_len_then_msg(conn, tx_msg)
    conn.close()
