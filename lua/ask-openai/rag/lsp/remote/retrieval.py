from dataclasses import dataclass
from pathlib import Path
from lsp.remote.comms import *
from lsp.model_qwen3_remote import encode_query
from lsp.storage import Chunk, load_all_datasets

@dataclass
class ChunkRanking:
    chunk: Chunk

    # score from 0 to 1
    embed_score: float = -1
    rerank_score: float = -1

    # order relative to other matches
    embed_position: int = -1
    rerank_position: int = -1

def semantic_grep(query: str, instruct: str | None = None) -> list[ChunkRanking]:
    if instruct is None:
        instruct = "Semantic grep of relevant code for display in neovim, using semantic_grep extension to telescope"

    # * encode query vector
    with logger.timer("encoding query"):
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
            # TODO dataclass
            msg = {"instruct": instruct, "query": query, "docs": docs}
            scores = client.rerank(msg)
            if not scores:
                raise Exception("rerank returned no scores")
            # assign new scores back to objects
            for c, rerank_score in zip(batch, scores):
                c.rerank_score = rerank_score

    # * sort by rerank score
    chunks.sort(key=lambda c: c.rerank_score, reverse=True)

    # * set rerank_positions
    for idx, c in enumerate(chunks):
        c.rerank_position = idx

    return chunks
