from pathlib import Path
from lsp.qwen3.known import get_known_inputs, verify_known_embeddings
from lsp.logs import get_logger, logging_fwk_to_console
from lsp.remote.comms import *
from lsp.model_qwen3_remote import encode_query
from lsp.storage import load_all_datasets
import rich

if __name__ == "__main__":

    logging_fwk_to_console("INFO")
    # logging_fwk_to_console("DEBUG")
    logger = get_logger(__name__)

    query = "where did I set the top_k for semantic grep?"
    with logger.timer("Send embedding to server"):
        with EmbedClient() as client:
            rx_embeddings = client.encode({'texts': query})

    # TODO de-duplicate instruct
    instruct = "Semantic grep of relevant code for display in neovim, using semantic_grep extension to telescope"
    query_vector = encode_query(query, instruct)

    # * load datasets
    dot_rag_dir = Path("~/repos/github/g0t4/ask-openai.nvim/.rag").expanduser().absolute()
    datasets = load_all_datasets(dot_rag_dir)

    dataset = datasets.for_file("test.py", vim_filetype="py")
    assert dataset

    top_k = 10  # TODO! 50
    scores, ids = dataset.index.search(query_vector, top_k)
    ids = ids[0]
    scores = scores[0]
    for id, score in zip(ids, scores):
        print(f'{id}/{score}')
        # TODO! batch the rerank, for now lets start w/ just one at a time
        # TODO! SORT TOO
        # TODO! SHOW ORDER BEFORE and AFTER compare on each
        chunk = datasets.get_chunk_by_faiss_id(id)
        if chunk is None:
            raise Exception("missing chunk?!" + id)

        with EmbedClient() as client:  # TODO reuse?
            # TODO inject SIG for better re-ranking?
            docs = [chunk.text]

            msg = {"instruct": instruct, "query": query, "docs": docs}
            scores = client.rerank(msg)
            rich.print(f'RR {scores=}')
            assert scores
            score = scores[0]
            # if score > 0.99:
            print(chunk.text)

#     # TODO rerank results
#
#     if not rx_embeddings:
#         exit(-1)
#
#     # prints here are ok b/c the intent is a one-off test of get embeddings, so show them!
#     print(f"Received {len(rx_embeddings)} embeddings:")
#     for e in rx_embeddings:
#         # print(f"  {e}")
#         print(f"  {len(e)}")
#
#     # ** validate scores
#     import numpy as np
#
#     verify_known_embeddings(np.array(rx_embeddings), "Qwen/Qwen3-Embedding-0.6B")
#
# def rerank_semantic_grep(query: str, documents: list[str]) -> list[float]:
#     # TODO do I want this here or push out into the client?
#     instruct = 'Does the document answer the user query?'
#     return rerank(instruct, query, documents)
