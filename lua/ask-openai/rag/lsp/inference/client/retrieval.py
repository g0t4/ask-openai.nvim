from dataclasses import dataclass
from pathlib import Path

import attrs
from lsp.inference.client.embedder import encode_query
from lsp.stoppers import Stopper
from lsp.storage import Datasets
from lsp.inference.client import *
from lsp.fs import get_config, relative_to_workspace

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

FAKE_STOPPER = Stopper("fake")

# FYI v2 pygls supports databinding args... but I had issues with j
@attrs.define
class LSPRagQueryRequest:
    query: str
    currentFileAbsolutePath: str | None = None
    vimFiletype: str | None = None
    instruct: str | None = None
    msgId: str = ""  # cannot bind underscores... this is not a bound param (LS handler sets it)
    languages: str = ""
    skipSameFile: bool = False
    topK: int = 50
    embedTopK: int | None = None
    # MAKE SURE TO GIVE DEFAULT VALUES IF NOT REQUIRED

async def semantic_grep(
    args: LSPRagQueryRequest,
    # TODO! fix datasets to not be so yucky
    datasets: Datasets,
    stopper: Stopper = FAKE_STOPPER,
) -> list[LSPRankedMatch]:
    all_languages = args.languages == "ALL"

    # TODO! if memory is an issue from re-ranker, investigate if you can at least disable cache for most requests
    #   see notes in qwen3_rerank.py module
    #   one idea: len(query) could decide (long query can benefit)... need to prove this first
    #   FYI right now cache is enabled.. maybe that is not the wise default?

    rerank_top_k = args.topK
    embed_top_k = args.embedTopK or args.topK
    query_embed_top_k = embed_top_k * 3 if args.skipSameFile else embed_top_k

    instruct = args.instruct
    if instruct is None:
        instruct = "Semantic grep of relevant code for display in neovim, using semantic_grep extension to telescope"
        # TODO try this instead after I geet a feel for re-rank with my original instruct:
        #   instruct_aka_task = "Given a user Query to find code in a repository, retrieve the most relevant Documents"
        #   PRN tweak/evaluate performance of different instruct/task descriptions?

    stopper.throw_if_stopped()
    # * encode query vector
    with logger.timer("encoding query"):
        query_vector = await encode_query(args.query, instruct)
        stopper.throw_if_stopped()  # PRN add in cancel/stop logic... won't matter though if the real task isn't cancellable (and just keeps running to completion)

    # * search embeddings
    if all_languages:
        scores = []
        ids = []

        # * top_k_per_lang
        # crude calculations for splitting top_k... these can and will be changed long-term
        #   consider just configuring how much per language in the all_languages config list (make each a configurable object)
        config = get_config()
        filter_languages = config.all_languages and len(config.all_languages) > 0
        if filter_languages:
            num_languages = 0
            for lang in config.all_languages:
                if lang in datasets.all_datasets:
                    num_languages += 1
        else:
            num_languages = len(datasets.all_datasets)
        if num_languages == 0:
            logger.error(f"all_languages={config.all_languages}, but no datasets match")
            raise Exception(f"all_languages={config.all_languages}, but no datasets match")
        top_k_per_lang = round(1.5 * query_embed_top_k / num_languages)  # over sample each language by 50%
        logger.info(f"{top_k_per_lang=} {config.all_languages=}")

        for lang, ds in datasets.all_datasets.items():
            if filter_languages and lang not in config.all_languages:
                logger.warn(f"skipping language: {lang}")
                continue

            logger.info(f"searching {lang} index")
            _scores, _ids = ds.index.search(query_vector, top_k_per_lang)
            scores.extend(_scores[0])
            ids.extend(_ids[0])
    else:
        dataset = datasets.for_file(args.currentFileAbsolutePath, vim_filetype=args.vimFiletype)
        if dataset is None:
            logger.error(f"No dataset for {args.currentFileAbsolutePath}")
            # return {"failed": True, "error": f"No dataset for {current_file_abs}"} # TODO return failure?
            raise Exception(f"No dataset for {args.currentFileAbsolutePath}")

        scores, ids = dataset.index.search(query_vector, query_embed_top_k)
        ids = ids[0]
        scores = scores[0]

    logger.info(f"ids len {len(ids)}")
    # logger.info(f"scores len {len(scores)}")
    # logger.info(f'{ids=}')
    # logger.info(f'{scores=}')

    # * lookup matching chunks (filter any exclusions on metadata)
    id_score_pairs = zip(ids, scores)
    if all_languages:
        # cross language lookups need to either:
        # 1. sample from each language evenly or weighted?
        # 2. sort by score? see how this works in reality...
        # FYI use #1 if scores don't really compare well across languages... I suspect they will though
        #
        # otherwise later languages (i.e. fish) configured late in all_languages will be skipped almost every time
        #   b/c I over sample each language in the hopes of not missing a few extra key chunks
        #   I don't take just top_k/num_languages
        id_score_pairs = sorted(id_score_pairs, key=lambda x: x[1], reverse=True)

    matches: list[LSPRankedMatch] = []
    num_embeds = 0
    for idx, (id, embed_score) in enumerate(id_score_pairs):

        chunk = datasets.get_chunk_by_faiss_id(id)
        if chunk is None:
            logger.warning("skipping missing chunk for id: %s", id)
            continue

        chunk_file_abs = chunk.file
        is_same_file = args.currentFileAbsolutePath == chunk_file_abs
        if args.skipSameFile and is_same_file:
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

        num_embeds += 1
        if num_embeds >= embed_top_k:
            # this is the case when we need to skipSameFile
            # - over query with query_embed_top_k
            # - also over query when doing all_languages (not just top_k/num_languages)
            break

    if len(matches) == 0:
        logger.warning(f"No matches found for {args.currentFileAbsolutePath=}")

    # * sort len(chunk.text)
    # so similar lengths are batched together given longest text (in tokens) dictates sequence length
    matches.sort(key=lambda c: len(c.text))

    def rerank_document(chunk: LSPRankedMatch):
        # [file: utils.py | lines 120–145]
        file = relative_to_workspace(chunk.file)
        start_line_base1 = chunk.start_line_base0 + 1
        end_line_base1 = chunk.end_line_base0 + 1
        return f"[ file: {file} | lines {start_line_base1}-{end_line_base1} ]\n" + chunk.text

    # * rerank batches
    BATCH_SIZE = 8
    for batch_num in range(0, len(matches), BATCH_SIZE):
        stopper.throw_if_stopped()
        batch = matches[batch_num:batch_num + BATCH_SIZE]
        docs = [rerank_document(c) for c in batch]
        logger.info(f"{args.msgId} re-rank batch {batch_num} len={len(batch)}")

        async with AsyncInferenceClient() as client:
            request = RerankRequest(instruct=instruct, query=args.query, docs=docs)
            scores = await client.rerank(request)
            if not scores:
                raise Exception("rerank returned no scores")
            # assign new scores back to objects
            for c, rerank_score in zip(batch, scores):
                c.rerank_score = rerank_score

    stopper.throw_if_stopped()

    # * sort score => then mark ranks
    matches.sort(key=lambda c: c.rerank_score, reverse=True)
    for idx, c in enumerate(matches):
        c.rerank_rank = idx

    if embed_top_k > rerank_top_k:
        logger.warn(f"{embed_top_k=} > {rerank_top_k=} truncating")
        matches = matches[:rerank_top_k]

    return matches
