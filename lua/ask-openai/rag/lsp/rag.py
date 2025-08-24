from pathlib import Path

import attrs
from pygls.workspace import TextDocument

from lsp.chunks.chunker import build_chunks_from_lines, get_file_hash_from_lines, RAGChunkerOptions
from lsp.logs import get_logger
from lsp.storage import Datasets, load_all_datasets
from lsp.inference.client.retrieval import *
from index.validate import DatasetsValidator
from lsp import fs

logger = get_logger(__name__)

datasets: Datasets

def load_model_and_indexes(dot_rag_dir: Path):
    global datasets
    datasets = load_all_datasets(dot_rag_dir)

def validate_rag_indexes():
    validator = DatasetsValidator(datasets)
    validator.validate()

# FYI v2 pygls supports databinding args... but I had issues with j
@attrs.define
class PyGLSCommandSemanticGrepArgs:
    query: str
    # MAKE SURE TO GIVE DEFAULT VALUES IF NOT REQUIRED
    currentFileAbsolutePath: str | None = None
    vimFiletype: str | None = None
    instruct: str | None = None

# PRN make top_k configurable (or other params)
async def handle_query(args: "PyGLSCommandSemanticGrepArgs", top_k=3, skip_same_file=False):
    # TODO!ASYNC

    # * parse and validate request parameters
    query = args.query
    if query is None or len(query) == 0:
        logger.error("[red bold][ERROR] No query provided")
        return {"failed": True, "error": "No query provided"}
    vim_filetype = args.vimFiletype
    current_file_abs = args.currentFileAbsolutePath
    instruct = args.instruct

    # * NEW SEMANTIC GREP PIPELINE
    matches = await semantic_grep(
        query=query,
        instruct=instruct,
        current_file_abs=current_file_abs,
        vim_filetype=vim_filetype,
        skip_same_file=skip_same_file,
        top_k=top_k,
        datasets=datasets,
    )
    return {
        "matches": matches,
    }

async def update_file_from_pygls_doc(lsp_doc: TextDocument, options: RAGChunkerOptions):
    file_path = Path(lsp_doc.path)

    hash = get_file_hash_from_lines(lsp_doc.lines)

    new_chunks = build_chunks_from_lines(file_path, hash, lsp_doc.lines, options)

    with logger.timer(f"update_file {fs.get_loggable_path(file_path)}"):
        await datasets.update_file(file_path, new_chunks)
