from pathlib import Path

from pygls.workspace import TextDocument

from lsp.chunker import build_chunks_from_lines, get_file_hash_from_lines, RAGChunkerOptions
from lsp.logs import get_logger
from lsp.storage import Datasets, load_all_datasets
from lsp.inference.client.retrieval import *
from index.validate import DatasetsValidator
from lsp import fs

logger = get_logger(__name__)

datasets: Datasets

def load_model_and_indexes(dot_rag_dir: Path, model_wrapper):
    global datasets
    datasets = load_all_datasets(dot_rag_dir)
    model_wrapper.todo_remove_this_eager_load_imports()

def validate_rag_indexes():
    validator = DatasetsValidator(datasets)
    validator.validate()

# PRN make top_k configurable (or other params)
async def handle_query(message, top_k=3, skip_same_file=False):
    # TODO!ASYNC

    # * parse and validate request parameters
    query = message.get("query")
    if query is None or len(query) == 0:
        logger.error("[red bold][ERROR] No query provided")
        return {"failed": True, "error": "No query provided"}
    vim_filetype: str | None = message.get("vim_filetype")
    current_file_abs: str = message.get("current_file_absolute_path")
    instruct = message.get("instruct")

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

def update_file_from_pygls_doc(lsp_doc: TextDocument, model_wrapper, options: RAGChunkerOptions):
    file_path = Path(lsp_doc.path)

    hash = get_file_hash_from_lines(lsp_doc.lines)

    new_chunks = build_chunks_from_lines(file_path, hash, lsp_doc.lines, options)

    with logger.timer(f"update_file {fs.get_loggable_path(file_path)}"):
        datasets.update_file(file_path, new_chunks, model_wrapper)
