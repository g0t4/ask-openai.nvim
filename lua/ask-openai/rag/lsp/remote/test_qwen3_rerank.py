from lsp.qwen3.known import get_known_inputs, verify_known_embeddings
from lsp.logs import get_logger, logging_fwk_to_console
from lsp.remote.comms import *

if __name__ == "__main__":

    logging_fwk_to_console("INFO")
    # logging_fwk_to_console("DEBUG")
    logger = get_logger(__name__)

    scoring_texts = get_known_inputs()

    file_chunk = "local M = {}\nlocal init = require(\"ask-openai\")\nlocal config = require(\"ask-openai.config\")\n\n-- FYI uses can add commands if that's what they want, they have the API to do so:\n\nfunction M.enable_predictions()\n    config.local_share.set_predictions_enabled()\n    init.start_predictions()\nend\n\nfunction M.disable_predictions()\n    config.local_share.set_predictions_disabled()\n    init.stop_predictions()\nend\n\nfunction M.toggle_predictions()\n    if config.local_share.are_predictions_enabled() then\n        M.disable_predictions()\n    else"
    hello_world = "Hello world"

    with logger.timer("Send embedding to server"):
        with EmbedClient() as client:
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

    verify_known_embeddings(np.array(rx_embeddings), "Qwen/Qwen3-Embedding-0.6B")

def rerank_semantic_grep(query: str, documents: list[str]) -> list[float]:
    # TODO do I want this here or push out into the client?
    instruct = 'Does the document answer the user query?'
    return rerank(instruct, query, documents)
