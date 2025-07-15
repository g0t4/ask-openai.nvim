import struct
import socket
import msgpack

from lsp.logs import get_logger, logging_fwk_to_console
from lsp.notes.hosted.sockets.comms import *

# time python3 -m lsp.notes.hosted.sockets.client

logging_fwk_to_console("INFO")
logger = get_logger(__name__)

def get_detailed_instruct(task_description: str, query: str) -> str:
    # *** INSTRUCTION!
    return f'Instruct: {task_description}\nQuery:{query}'

# Each query must come with a one-sentence instruction that describes the task
task = 'Given a web search query, retrieve relevant passages that answer the query'
queries = [
    get_detailed_instruct(task, 'What is the capital of China?'),
    get_detailed_instruct(task, 'Explain gravity'),
]
# No need to add instruction for retrieval documents
documents = [
    "The capital of China is Beijing.",
    "Gravity is a force that attracts two bodies towards each other. It gives weight to physical objects and is responsible for the movement of planets around the sun.",
]
scoring_texts = queries + documents

# all_ever_scores = []
# for _ in range(1, 100):
#     embeddings = encode(input_texts)
#     query_embeddings = embeddings[:2]  # first two are queries
#     passage_embeddings = embeddings[2:]  # last two are documents
#     scores = (query_embeddings @ passage_embeddings.T)
#     logger.debug(f'{scores=}')
#     all_ever_scores.append(scores)
#     from numpy.testing import assert_array_almost_equal
#     expected_scores = [[0.7645568251609802, 0.14142508804798126], [0.13549736142158508, 0.5999549627304077]]
#     assert_array_almost_equal(scores.detach().numpy(), expected_scores, decimal=6)

file_chunk = "local M = {}\nlocal init = require(\"ask-openai\")\nlocal config = require(\"ask-openai.config\")\n\n-- FYI uses can add commands if that's what they want, they have the API to do so:\n\nfunction M.enable_predictions()\n    config.local_share.set_predictions_enabled()\n    init.start_predictions()\nend\n\nfunction M.disable_predictions()\n    config.local_share.set_predictions_disabled()\n    init.stop_predictions()\nend\n\nfunction M.toggle_predictions()\n    if config.local_share.are_predictions_enabled() then\n        M.disable_predictions()\n    else"
hello_world = "Hello world"
tx_msg = {'texts': scoring_texts}

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
    conn = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    # client.connect(("localhost", 8015))
    conn.connect(("ollama", 8015))

    send_len_then_msg(conn, tx_msg)
    rx_msg = recv_len_then_msg(conn)

    conn.close()

if not rx_msg:
    logger.debug(f'unexpected empty response: {rx_msg=}')
    exit(-1)

rx_embedding = rx_msg['embedding']

logger.debug(f"Received {len(rx_embedding)} embeddings:")
for e in rx_embedding:
    logger.debug(f"  {e}")
