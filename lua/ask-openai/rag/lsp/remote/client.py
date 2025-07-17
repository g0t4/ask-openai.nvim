from lsp.qwen3.known import get_known_inputs
from ..logs import get_logger, logging_fwk_to_console
from .comms import *

# time python3 -m lsp.notes.hosted.sockets.client

# logging_fwk_to_console("WARN")
logging_fwk_to_console("INFO")
# logging_fwk_to_console("DEBUG")

logger = get_logger(__name__)

scoring_texts = get_known_inputs()

file_chunk = "local M = {}\nlocal init = require(\"ask-openai\")\nlocal config = require(\"ask-openai.config\")\n\n-- FYI uses can add commands if that's what they want, they have the API to do so:\n\nfunction M.enable_predictions()\n    config.local_share.set_predictions_enabled()\n    init.start_predictions()\nend\n\nfunction M.disable_predictions()\n    config.local_share.set_predictions_disabled()\n    init.stop_predictions()\nend\n\nfunction M.toggle_predictions()\n    if config.local_share.are_predictions_enabled() then\n        M.disable_predictions()\n    else"
hello_world = "Hello world"
test_inputs = {'texts': scoring_texts}

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
    with EmbedClient() as client:
        rx_embeddings = client.encode(test_inputs)

if not rx_embeddings:
    exit(-1)

# prints here are ok b/c the intent is a one-off test of get embeddings, so show them!
print(f"Received {len(rx_embeddings)} embeddings:")
for e in rx_embeddings:
    # print(f"  {e}")
    print(f"  {len(e)}")

# ** validate scores

import numpy as np
from numpy.testing import assert_array_almost_equal

np_embeddings = np.array(rx_embeddings)
query_embeddings = np_embeddings[:2]  # first two are queries
passage_embeddings = np_embeddings[2:]  # last two are documents
scores = (query_embeddings @ passage_embeddings.T)
print(f'{scores=}')

expected_scores = [[0.7645568251609802, 0.14142508804798126], [0.13549736142158508, 0.5999549627304077]]
print(f'{expected_scores=}')

assert_array_almost_equal(scores, expected_scores, decimal=3)
