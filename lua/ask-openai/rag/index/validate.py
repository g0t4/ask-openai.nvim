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

    print(f"{dataset.index.ntotal=}")
    # print(f"{dataset.chunks_by_file.keys()=}")
    # print(f"{dataset.stat_by_path.keys()=}")

    ids = faiss.vector_to_array(dataset.index.id_map)

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
    if len(ids) != dataset.index.ntotal:
        logger.info(f"{len(ids)=}")
        logger.info(f"{dataset.index.ntotal=}")
        logger.error(f"ERROR - VECTORS COUNT DOES NOT MATCH ID COUNTS")

    # TODO find a way to verify the vectors "make sense"... relative to ID map...
