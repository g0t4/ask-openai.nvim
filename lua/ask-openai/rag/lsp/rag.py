from pathlib import Path

import attrs
from pygls.workspace import TextDocument

from lsp.chunks.chunker import build_chunks_from_lines, get_file_hash_from_lines, RAGChunkerOptions
from lsp.logs import get_logger
from lsp.stoppers import Stopper, create_stopper, remove_stopper
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
    validator.validate_datasets()

@attrs.define
class LSPSemanticGrepResult:
    """ Either return matches OR an error string, nothing else matters."""
    matches: list = []
    error: str | None = None

class LSPResponseErrors:
    NO_RAG_DIR = "No .rag dir"
    CANCELLED = "Client cancelled query"

async def handle_semantic_grep_ls_command(args: LSPSemanticGrepRequest) -> LSPSemanticGrepResult:
    stopper = create_stopper(args.msgId)
    try:
        if fs.is_no_rag_dir():
            return LSPSemanticGrepResult(error=LSPResponseErrors.NO_RAG_DIR)

        # TODO! REVIEW the ASYNC (i.e. for file ops? or other async capable ops)

        query = args.query
        if query is None or len(query) == 0:
            logger.info("No query provided")
            return LSPSemanticGrepResult(error="No query provided")

        stopper.throw_if_stopped()

        matches = await semantic_grep(
            args=args,
            datasets=datasets,
            stopper=stopper,
        )

        return LSPSemanticGrepResult(matches=matches)
    finally:
        remove_stopper(args.msgId)

async def update_file_from_pygls_doc(lsp_doc: TextDocument, options: RAGChunkerOptions):
    file_path = Path(lsp_doc.path)

    hash = get_file_hash_from_lines(lsp_doc.lines)

    new_chunks = build_chunks_from_lines(file_path, hash, lsp_doc.lines, options)

    with logger.timer(f"update_file {fs.get_loggable_path(file_path)}"):
        await datasets.update_file(file_path, new_chunks)
