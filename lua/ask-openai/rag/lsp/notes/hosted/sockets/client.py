from lsp.logs import get_logger, logging_fwk_to_console

import socket
import msgpack

logging_fwk_to_console("INFO")
logger = get_logger(__name__)

with logger.timer("Send embedding to server"):

    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.connect("/tmp/embed.sock")

    payload = msgpack.packb({'text': "Hello world"}, use_bin_type=True)
    client.sendall(payload)

    data = client.recv(65536)
    result = msgpack.unpackb(data, raw=False)

print(result['embedding'])
