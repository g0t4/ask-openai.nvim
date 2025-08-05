from pathlib import Path
import sys
from indexer import load_prior_data
from lsp.logs import get_logger, logging_fwk_to_console
import faiss
import numpy as np

# usage:
#   python3 -m index.inspecter $(_repo_root)/.rag

logger = get_logger(__name__)
logging_fwk_to_console(level="DEBUG")

rag_dir = Path(sys.argv[1])
dataset = load_prior_data(rag_dir, "py")

print(f"{dataset.index.ntotal=}")
print(f"{dataset.chunks_by_file.keys()=}")
print(f"{dataset.stat_by_path.keys()=}")

ids = faiss.vector_to_array(dataset.index.id_map)

# * test for duplicate IDs
# test duplicate logic:
#   ids = np.append(ids, ids[-1])
#
duplicates = set()
for id in sorted(ids):
    if id in duplicates:
        logger.error(f"ERROR - FOUND DUPLICATE ID {id}")
        break
    duplicates.add(id)

# * compare # vectors to # IDs
if len(ids) != dataset.index.ntotal:
    print(f"{len(ids)=}")
    print(f"{dataset.index.ntotal=}")
    logger.error(f"ERROR - VECTORS COUNT DOES NOT MATCH ID COUNTS")

# TODO find a way to verify the vectors "make sense"... relative to ID map...
