from pathlib import Path

import attrs
from pygls.workspace import TextDocument

from chunks.chunker import build_chunks_from_lines, get_file_hash_from_lines, RAGChunkerOptions
from rag.logs import get_logger
from language_server.stoppers import Stopper, create_stopper, remove_stopper
from index.storage import Datasets, load_all_datasets
from inference.client.retrieval import *
from index import fs

logger = get_logger(__name__)

datasets: Datasets

def load_model_and_indexes(dot_rag_dir: Path):
    global datasets
    datasets = load_all_datasets(dot_rag_dir)

async def update_file_from_pygls_doc(lsp_doc: TextDocument, options: RAGChunkerOptions, _passed_datasets: Datasets):
    file_path = Path(lsp_doc.path)

    with logger.timer(f"update_file {fs.get_loggable_path(file_path)}"):
        hash = get_file_hash_from_lines(lsp_doc.lines)
        # FYI you can check hash for changes, but remember this is off of disk and you only update that on commit
        #   so really there's no point to ask if changed, b/c only going to be saving materially if altering it
        #   in which case it's always gonna look altered at least LS side
        new_chunks = build_chunks_from_lines(file_path, hash, lsp_doc.lines, options)  # PRN await
        await _passed_datasets.update_file(file_path, new_chunks)
