from dataclasses import dataclass
from pathlib import Path
from lsp.qwen3.known import get_known_inputs, verify_known_embeddings
from lsp.logs import get_logger, logging_fwk_to_console
from lsp.remote.comms import *
from lsp.model_qwen3_remote import encode_query
from lsp.storage import Chunk, load_all_datasets
import rich

def format_score(score: float) -> str:
    """score rounded to nearest 4 decimals"""
    return f'{score:.4f}'
    # TODO to shared spot

@dataclass
class ChunkRanking:
    chunk: Chunk

    # score from 0 to 1
    embed_score: float = -1
    rerank_score: float = -1

    # order relative to other matches
    embed_position: int = -1
    rerank_position: int = -1

if __name__ == "__main__":

    logging_fwk_to_console("INFO")
    # logging_fwk_to_console("DEBUG")
    logger = get_logger(__name__)

    # * instruct / task
    # FYI! sync any changes to instruct to the respective python re-ranking code
    instruct_aka_task = "Semantic grep of relevant code for display in neovim, using semantic_grep extension to telescope"

    # * encode query vector
    query = "where did I set the top_k for semantic grep?"
    with logger.timer("encoding query"):
        query_vector = encode_query(query, instruct_aka_task)

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
    chunks: list[ChunkRanking] = []
    for idx, (id, embed_score) in enumerate(zip(ids, scores)):
        chunk = datasets.get_chunk_by_faiss_id(id)
        if chunk is None:
            raise Exception("missing chunk?!" + id)
        chunks.append(ChunkRanking(
            chunk=chunk,
            embed_score=embed_score,
            embed_position=idx,
        ))

    # * sort len(chunk.text)
    # so similar lengths are batched together given longest text (in tokens) dictates sequence length
    chunks.sort(key=lambda c: len(c.chunk.text))

    # * rerank batches
    BATCH_SIZE = 8
    for batch_num in range(0, len(chunks), BATCH_SIZE):
        batch = chunks[batch_num:batch_num + BATCH_SIZE]
        docs = [c.chunk.text for c in batch]

        with EmbedClient() as client:
            msg = {"instruct": instruct_aka_task, "query": query, "docs": docs}
            scores = client.rerank(msg)
            if not scores:
                raise Exception("rerank returned no scores")
            # assign new scores back to objects
            for c, rerank_score in zip(batch, scores):
                c.rerank_score = rerank_score

    # * sort by rerank score
    chunks.sort(key=lambda c: c.rerank_score, reverse=True)

    # * dump details
    for i, c in enumerate(chunks):
        rich.print(f'{i} / {c.chunk.id}: rerank={format_score(c.rerank_score)} embed={format_score(c.embed_score)}')
        if logger.isEnabledForDebug():
            print(c.chunk.text)
