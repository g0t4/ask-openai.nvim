from lsp.inference.qwen3.known import get_known_inputs, verify_qwen3_known_embeddings
from lsp.logs import get_logger, logging_fwk_to_console
from lsp.inference.client import *

if __name__ == "__main__":

    logging_fwk_to_console("INFO")
    # logging_fwk_to_console("DEBUG")
    logger = get_logger(__name__)

    scoring_texts = get_known_inputs()

    file_chunk = "local M = {}\nlocal init = require(\"ask-openai\")\nlocal config = require(\"ask-openai.config\")\n\n-- FYI uses can add commands if that's what they want, they have the API to do so:\n\nfunction M.enable_predictions()\n    config.local_share.set_predictions_enabled()\n    init.start_predictions()\nend\n\nfunction M.disable_predictions()\n    config.local_share.set_predictions_disabled()\n    init.stop_predictions()\nend\n\nfunction M.toggle_predictions()\n    if config.local_share.are_predictions_enabled() then\n        M.disable_predictions()\n    else"
    hello_world = "Hello world"

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
        with InferenceClient() as client:
            rx_embeddings = client.encode({'texts': scoring_texts})

    if not rx_embeddings:
        exit(-1)

    # prints here are ok b/c the intent is a one-off test of get embeddings, so show them!
    print(f"Received {len(rx_embeddings)} embeddings:")
    for e in rx_embeddings:
        # print(f"  {e}")
        print(f"  {len(e)}")

    # ** validate scores
    import numpy as np

    verify_qwen3_known_embeddings(np.array(rx_embeddings), "Qwen/Qwen3-Embedding-0.6B")
