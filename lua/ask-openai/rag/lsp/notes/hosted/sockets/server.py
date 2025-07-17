#
# z rag
# time python3 -m lsp.notes.hosted.sockets.server

print('imports...')

import socket
import signal
import rich

from lsp.notes.hosted.sockets import qwen3
from lsp.logs import Timer, get_logger, logging_fwk_to_console
from lsp.notes.hosted.sockets.comms import *

print('imports done')

logging_fwk_to_console("WARN")
# logging_fwk_to_console("INFO")
# logging_fwk_to_console("DEBUG")
logger = get_logger(__name__)

def encode(texts: list[str]):
    # logger.debug(texts)
    vec = qwen3.encode(texts)
    logger.debug(vec)
    return vec.tolist()

print('testing known embeddings...')
qwen3.test_known_embeddings()

print('opening socket')

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
# set REUSEADDR so TIME-WAIT ports don't block restarting server, else wait upwards of a minute
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

server.bind(("0.0.0.0", 8015))
server.listen()

clear_iterm_scrolback = "\x1b]1337;ClearScrollback\a"
print(clear_iterm_scrolback)
rich.print("[green bold]Server ready...")

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

    with Timer() as encode_timer:
        embedding = encode(rx_text)

    tx_msg = {'embeddings': embedding}
    send_len_then_msg(conn, tx_msg)
    conn.close()

    rich.print(f"[blue]encoded {len(rx_text)} in {encode_timer.elapsed_ms():.3f} ms")
