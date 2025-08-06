from pathlib import Path
import sys
from lsp.storage import load_all_datasets
from lsp.logs import get_logger, logging_fwk_to_console
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

any_problems = False

for dataset in datasets.all_datasets.values():
    # PRN consider moving this onto the RAGDataset type or into an auxillary type for reuse on LSP startup, elsewhere

    num_vectors_based_on_ntotal = dataset.index_view.num_vectors()

    logger.info(f"{num_vectors_based_on_ntotal=}")

    any_problem_with_this_dataset = False
    ids = dataset.index_view.ids

    # * compare # vectors to # IDs
    if len(ids) != num_vectors_based_on_ntotal:
        logger.info(f"{len(ids)=}")
        logger.info(f"{num_vectors_based_on_ntotal=}")
        logger.error(f"{len(ids)=} should match {num_vectors_based_on_ntotal} number of vectors in faiss index, but does not.")

    # * test for duplicate IDs
    duplicate_ids = list(dataset.index_view._check_for_duplicate_ids())
    # PRN turn into an index_view.exit_if_duplicates()?
    num_vectors_based_on_ids = sum([count for _, count in duplicate_ids])
    num_ids_based_on_ids = len(duplicate_ids)
    num_chunks_based_on_chunks = sum([len(file) for file in dataset.chunks_by_file.values()])

    for id, count in duplicate_ids:
        if count <= 1:
            continue
        any_problem_with_this_dataset = True
        chunk = datasets.get_chunk_by_faiss_id(id)
        if chunk is None:
            logger.error(f"Duplicate ID found: {id} - {count}x - missing chunk too")
        else:
            logger.error(f"Duplicate ID found: {id} with {count}x - {chunk.file} L{chunk.start_line}-{chunk.end_line}")

    if num_ids_based_on_ids != num_chunks_based_on_chunks:
        any_problem_with_this_dataset = True
        logger.error(f"chunk count mismatch: {num_ids_based_on_ids=} != {num_chunks_based_on_chunks=}")
    if num_vectors_based_on_ntotal != num_vectors_based_on_ids:
        any_problem_with_this_dataset = True
        logger.error(f"vectors count mismatch: {num_vectors_based_on_ntotal=} != {num_vectors_based_on_ids=}")

    if any_problem_with_this_dataset:
        # look for mismatch in datasets (i.e. missing chunks or vectors for old chunks)
        logger.info(f'{num_vectors_based_on_ids=} {num_ids_based_on_ids=}')
        logger.info(f'{num_chunks_based_on_chunks=}')

    any_problems = any_problems or any_problem_with_this_dataset
    # TODO find a way to verify the vectors "make sense"... relative to ID map...

if any_problems:
    logger.error("[bold red]AT LEAST ONE PROBLEM DISCOVERED")
    sys.exit(1)
else:
    logger.info("[bold green]ALL CHECKS PASS!")
