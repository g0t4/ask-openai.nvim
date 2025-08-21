from dataclasses import dataclass
from pathlib import Path
from lsp.remote.comms import *
from lsp.model_qwen3_remote import encode_query
from lsp.storage import Chunk, load_all_datasets

@dataclass
class RankedMatch:
    # TODO nuke this version now that I use LSPRankedMatch
    chunk: Chunk

    # score from 0 to 1
    embed_score: float = -1
    rerank_score: float = -1

    # order relative to other matches
    embed_rank: int = -1
    rerank_rank: int = -1

@dataclass
class LSPRankedMatch:
    text: str
    file: str
    # using _base0 b/c this is serialized to clients so it must be clear as base0, clients can wrap and add .base0.start_line or .base1.start_line if desired
    # also server side I am not doing much with this, mostly just serialize responses to client so I don't need easy access to base1 on this type
    start_line_base0: int
    start_column_base0: int
    end_line_base0: int
    end_column_base0: int | None
    type: str
    signature: str

    # score from 0 to 1
    embed_score: float = -1
    rerank_score: float = -1

    # order relative to other matches
    embed_rank: int = -1
    rerank_rank: int = -1

def semantic_grep(query: str, current_file_abs: str | Path, vim_filetype: str | None = None, instruct: str | None = None) -> list[LSPRankedMatch]:
    if instruct is None:
        instruct = "Semantic grep of relevant code for display in neovim, using semantic_grep extension to telescope"

    # * encode query vector
    with logger.timer("encoding query"):
        query_vector = encode_query(query, instruct)

    # * load datasets
    dot_rag_dir = Path("~/repos/github/g0t4/ask-openai.nvim/.rag").expanduser().absolute()
    datasets = load_all_datasets(dot_rag_dir)
    dataset = datasets.for_file(current_file_abs, vim_filetype=vim_filetype)
    assert dataset

    # * search embeddings
    top_k = 50
    scores, ids = dataset.index.search(query_vector, top_k)
    ids = ids[0]
    scores = scores[0]

    # * lookup matching chunks
    chunks: list[LSPRankedMatch] = []
    for idx, (id, embed_score) in enumerate(zip(ids, scores)):
        chunk = datasets.get_chunk_by_faiss_id(id)
        if chunk is None:
            logger.warning("skipping missing chunk for id: %s", id)
            continue
        match = LSPRankedMatch(
            text=chunk.text,
            file=chunk.file,
            start_line_base0=chunk.base0.start_line,
            start_column_base0=chunk.base0.start_column,
            end_line_base0=chunk.base0.end_line,
            end_column_base0=chunk.base0.end_column,
            type=chunk.type,
            signature=chunk.signature,

            # TODO are these correct for embed score/rank?
            embed_score=embed_score,
            embed_rank=idx,
        )

        matches.append(match)

    # TODO! do I need to sort by embed_score first? IIRC these are sorted in order BUT DOUBLE CHEK

    # * sort len(chunk.text)
    # so similar lengths are batched together given longest text (in tokens) dictates sequence length
    chunks.sort(key=lambda c: len(c.chunk.text))

    # * rerank batches
    BATCH_SIZE = 8
    for batch_num in range(0, len(chunks), BATCH_SIZE):
        batch = chunks[batch_num:batch_num + BATCH_SIZE]
        docs = [c.chunk.text for c in batch]

        with EmbedClient() as client:
            request = RerankRequest(instruct=instruct, query=query, docs=docs)
            scores = client.rerank(request)
            if not scores:
                raise Exception("rerank returned no scores")
            # assign new scores back to objects
            for c, rerank_score in zip(batch, scores):
                c.rerank_score = rerank_score

    # * sort by rerank score
    chunks.sort(key=lambda c: c.rerank_score, reverse=True)

    # * set rerank_ranks
    # FYI sort by rerank_score BEFORE computing rerank_rank
    for idx, c in enumerate(chunks):
        c.rerank_rank = idx

    return chunks
