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
    #   18-20ms with "hello world"
    #   then my chunk (below)... holy F 21ms?! qwen3 full precision!
    #

    client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    # client.connect(("localhost", 8015))
    client.connect(("ollama", 8015))

    chunk = "local M = {}\nlocal init = require(\"ask-openai\")\nlocal config = require(\"ask-openai.config\")\n\n-- FYI uses can add commands if that's what they want, they have the API to do so:\n\nfunction M.enable_predictions()\n    config.local_share.set_predictions_enabled()\n    init.start_predictions()\nend\n\nfunction M.disable_predictions()\n    config.local_share.set_predictions_disabled()\n    init.stop_predictions()\nend\n\nfunction M.toggle_predictions()\n    if config.local_share.are_predictions_enabled() then\n        M.disable_predictions()\n    else"
    hello = "Hello world"
    payload = msgpack.packb({'text': chunk}, use_bin_type=True)
    client.sendall(payload)

    data = client.recv(65536)
    result = msgpack.unpackb(data, raw=False)

print(len(result['embedding'][0]))
