from pathlib import Path
from lsp.qwen3.known import get_known_inputs, verify_known_embeddings
from lsp.logs import get_logger, logging_fwk_to_console
from lsp.remote.comms import *
from lsp.model_qwen3_remote import encode_query
from lsp.storage import load_all_datasets
import rich

def format_score(score: float) -> str:
    """score rounded to nearest 4 decimals"""
    return f'{score:.4f}'
    # TODO to shared spot

if __name__ == "__main__":

    logging_fwk_to_console("INFO")
    # logging_fwk_to_console("DEBUG")
    logger = get_logger(__name__)

    # * encode query vector
    query = "where did I set the top_k for semantic grep?"
    with logger.timer("Send embedding to server"):
        with EmbedClient() as client:
            rx_embeddings = client.encode({'texts': query})

    # TODO! I think I need a better instruct? does this convey yes/no?
    # TODO! centralize instructs and query text so I always use the same on encode and rerank
    # instruct = 'Does the document answer the user query?'
    instruct = "Semantic grep of relevant code for display in neovim, using semantic_grep extension to telescope"

    query_vector = encode_query(query, instruct)

    # * load datasets
    dot_rag_dir = Path("~/repos/github/g0t4/ask-openai.nvim/.rag").expanduser().absolute()
    datasets = load_all_datasets(dot_rag_dir)
    dataset = datasets.for_file("test.py", vim_filetype="py")
    assert dataset

    # * search embeddings
    top_k = 50
    scores, ids = dataset.index.search(query_vector, top_k)
    ids = ids[0]
    scores = scores[0]

    # * lookup matching chunks
    chunks = []
    for id, embed_score in zip(ids, scores):
        chunk = datasets.get_chunk_by_faiss_id(id)
        if chunk is None:
            raise Exception("missing chunk?!" + id)
        chunks.append({"chunk": chunk, "embed_score": embed_score})

    # * sort len(chunk.text)
    # so similar lengths are batched together given longest text (in tokens) dictates sequence length
    chunks.sort(key=lambda c: len(c["chunk"].text))

    # * rerank batches
    BATCH_SIZE = 8
    for batch_num in range(0, len(chunks), BATCH_SIZE):
        batch = chunks[batch_num:batch_num + BATCH_SIZE]
        docs = [c["chunk"].text for c in batch]

        with EmbedClient() as client:
            msg = {"instruct": instruct, "query": query, "docs": docs}
            scores = client.rerank(msg)
            if not scores:
                raise Exception("rerank returned no scores")
            # assign new scores back to objects
            for c, rerank_score in zip(batch, scores):
                c["rerank_score"] = rerank_score

    # * sort by rerank score
    chunks.sort(key=lambda c: c["rerank_score"], reverse=True)

    # * dump details
    for i, c in enumerate(chunks):
        rich.print(f'{i} / {c["chunk"].id}: rerank={format_score(c["rerank_score"])} embed={format_score(c["embed_score"])}')
        rich.print(c["chunk"].text)
