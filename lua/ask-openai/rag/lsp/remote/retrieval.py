from dataclasses import dataclass
from pathlib import Path
from lsp.remote.comms import *
from lsp.model_qwen3_remote import encode_query
from lsp.storage import Chunk, Datasets, load_all_datasets

@dataclass
class LSPRankedMatch:
    id: str
    id_int: str
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
    # file_hash: str # not used

    # score from 0 to 1
    embed_score: float = -1
    rerank_score: float = -1

    # order relative to other matches
    embed_rank: int = -1
    rerank_rank: int = -1

def semantic_grep(
    query: str,
    current_file_abs: str | Path,
    vim_filetype: str | None = None,
    instruct: str | None = None,
    skip_same_file=False,
    top_k: int = 50,
    # TODO fix datasets to not be so yucky
    datasets: Datasets | None = None,
) -> list[LSPRankedMatch]:
    if instruct is None:
        instruct = "Semantic grep of relevant code for display in neovim, using semantic_grep extension to telescope"
        # TODO try this instead after I geet a feel for re-rank with my original instruct:
        #   instruct_aka_task = "Given a user Query to find code in a repository, retrieve the most relevant Documents"
        #   PRN tweak/evaluate performance of different instruct/task descriptions?

    # * encode query vector
    with logger.timer("encoding query"):
        query_vector = encode_query(query, instruct)

    if datasets is None:
        logger.error("DATASETS must be loaded and passed")
        raise Exception("MISSING DATASET(S) PLURAL")

    dataset = datasets.for_file(current_file_abs, vim_filetype=vim_filetype)
    if dataset is None:
        logger.error(f"No dataset")
        # return {"failed": True, "error": f"No dataset for {current_file_abs}"} # TODO return failure?
        raise Exception(f"No dataset for {current_file_abs}")

    # * search embeddings
    scores, ids = dataset.index.search(query_vector, top_k)
    ids = ids[0]
    scores = scores[0]

    # * lookup matching chunks (filter any exclusions on metadata)
    matches: list[LSPRankedMatch] = []
    for idx, (id, embed_score) in enumerate(zip(ids, scores)):
        # print(id, embed_score) # nice way to verify initial sort (indeed is descending by embed_score)
        if len(matches) >= top_k:
            break

        chunk = datasets.get_chunk_by_faiss_id(id)
        if chunk is None:
            logger.warning("skipping missing chunk for id: %s", id)
            continue

        chunk_file_abs = chunk.file
        is_same_file = current_file_abs == chunk_file_abs
        if skip_same_file and is_same_file:
            logger.warning(f"Skip match in same file")
            continue

        logger.debug(f"matched {chunk.file}:base0-L{chunk.base0.start_line}-{chunk.base0.end_line}")

        match = LSPRankedMatch(
            id=chunk.id,
            id_int=chunk.id_int,
            text=chunk.text,
            file=chunk.file,
            start_line_base0=chunk.base0.start_line,
            start_column_base0=chunk.base0.start_column,
            end_line_base0=chunk.base0.end_line,
            end_column_base0=chunk.base0.end_column,
            type=chunk.type,
            signature=chunk.signature,

            # capture idx as rank before any sorting (i.e. text len below)
            embed_score=embed_score.item(),  # numpy.float32 not serializable, use .item()
            embed_rank=idx,
        )

        matches.append(match)

    if len(matches) == 0:
        logger.warning(f"No matches found for {current_file_abs=}")

    # * sort len(chunk.text)
    # so similar lengths are batched together given longest text (in tokens) dictates sequence length
    matches.sort(key=lambda c: len(c.text))

    # * rerank batches
    BATCH_SIZE = 8
    for batch_num in range(0, len(matches), BATCH_SIZE):
        batch = matches[batch_num:batch_num + BATCH_SIZE]
        docs = [c.text for c in batch]

        with EmbedClient() as client:
            request = RerankRequest(instruct=instruct, query=query, docs=docs)
            scores = client.rerank(request)
            if not scores:
                raise Exception("rerank returned no scores")
            # assign new scores back to objects
            for c, rerank_score in zip(batch, scores):
                c.rerank_score = rerank_score

    # * sort score => then mark ranks
    matches.sort(key=lambda c: c.rerank_score, reverse=True)
    for idx, c in enumerate(matches):
        c.rerank_rank = idx

    return matches
