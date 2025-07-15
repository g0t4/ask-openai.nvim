from lsp.logs import get_logger, logging_fwk_to_console

import socket
import msgpack

# time python3 -m lsp.notes.hosted.sockets.client

logging_fwk_to_console("INFO")
logger = get_logger(__name__)

with logger.timer("Send embedding to server"):
    # intfloat/e5-base-v2 model timing:
    #   input: [{'text': "Hello world"}]
    #
    #   local:
    #   60ms initial
    #   50ms second
    #   40ms 3+ (mostly)
    #   both with AF_UNIX and AF_INET sockets
    #
    #   remote: down to 18ms when process is primed (request 3+)
    #
    # qwen3-embedding-0.6B full precision
    #   local sockets => 50ms! not bad at all (small query doc)
    #   remote
    #

    client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    # client.connect(("localhost", 8015))
    client.connect(("ollama", 8015))

    payload = msgpack.packb({'text': "Hello world"}, use_bin_type=True)
    client.sendall(payload)

    data = client.recv(65536)
    result = msgpack.unpackb(data, raw=False)

# print(result['embedding'])
