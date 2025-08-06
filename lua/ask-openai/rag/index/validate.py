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

def error_duplicate_id(id):
    logger.error(f"Duplicate ID found: {id}")
    # chunk =

    sys.exit(1)

for dataset in datasets.all_datasets.values():
    # print(f"{dataset=}")
    # PRN consider moving this onto the RAGDataset type or into an auxillary type for reuse on LSP startup, elsewhere

    num_vectors = dataset.index_view.num_vectors()

    logger.info(f"{num_vectors=}")
    # print(f"{dataset.chunks_by_file.keys()=}")
    # print(f"{dataset.stat_by_path.keys()=}")

    ids = dataset.index_view.ids

    # * test for duplicate IDs
    # test duplicate logic:
    #   ids = np.append(ids, ids[-1])
    #
    duplicates = set()
    for id in sorted(ids):
        if id in duplicates:
            error_duplicate_id(id)
            break
        duplicates.add(id)

    # * compare # vectors to # IDs
    if len(ids) != num_vectors:
        logger.info(f"{len(ids)=}")
        logger.info(f"{num_vectors=}")
        logger.error(f"{len(ids)=} should match {num_vectors} number of vectors in faiss index, but does not.")

    # TODO find a way to verify the vectors "make sense"... relative to ID map...
