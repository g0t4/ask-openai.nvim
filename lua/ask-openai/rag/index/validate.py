from pathlib import Path
import sys
from lsp.storage import load_prior_data, load_all_datasets
from lsp.logs import get_logger, logging_fwk_to_console
import faiss
import numpy as np

# usage:
#   python3 -m index.validate $(_repo_root)/.rag

logger = get_logger(__name__)
logging_fwk_to_console(level="DEBUG")

rag_dir = Path(sys.argv[1])
datasets = load_all_datasets(rag_dir)

def print_type(what):
    if type(what) is np.ndarray:
        print(f'{type(what)} shape: {what.shape} {what.dtype}')
        return

    print(type(what))

for dataset in datasets.all_datasets.values():
    # print(f"{dataset=}")
    # PRN consider moving this onto the RAGDataset type or into an auxillary type for reuse on LSP startup, elsewhere

    num_vectors = dataset.index_view.num_vectors()

    logger.info(f"{num_vectors=}")
    # print(f"{dataset.chunks_by_file.keys()=}")
    # print(f"{dataset.stat_by_path.keys()=}")

    ids = dataset.index_view.ids
    print_type(ids)

    # * test for duplicate IDs
    # test duplicate logic:
    #   ids = np.append(ids, ids[-1])
    #
    duplicate_ids = list(dataset.index_view._check_for_duplicate_ids())
    # PRN turn into an index_view.exit_if_duplicates()?
    num_vectors_based_on_ids = sum([count for _, count in duplicate_ids])
    num_ids_based_on_ids = len(duplicate_ids)
    num_chunks_based_on_chunks = sum([len(file) for file in dataset.chunks_by_file.values()])

    # look for mismatch in datasets (i.e. missing chunks or vectors for old chunks)
    print(f'{num_vectors_based_on_ids=} {num_ids_based_on_ids=}')
    print(f'{num_chunks_based_on_chunks=}')
    if num_ids_based_on_ids != num_chunks_based_on_chunks:
        print(f"chunk count mismatch: {num_ids_based_on_ids=} != {num_chunks_based_on_chunks=}")
    if num_vectors != num_vectors_based_on_ids:
        print(f"vectors count mismatch: {num_vectors=} != {num_vectors_based_on_ids=}")

    for id, count in duplicate_ids:
        if count <= 1:
            continue
        logger.error(f"Duplicate ID found: {id} with {count}x")
        chunk = datasets.get_chunk_by_faiss_id(id)
        if chunk is None:
            print("NO CHUNK")
        else:
            print(chunk.file)

    # * compare # vectors to # IDs
    if len(ids) != num_vectors:
        logger.info(f"{len(ids)=}")
        logger.info(f"{num_vectors=}")
        logger.error(f"{len(ids)=} should match {num_vectors} number of vectors in faiss index, but does not.")

    # TODO find a way to verify the vectors "make sense"... relative to ID map...
