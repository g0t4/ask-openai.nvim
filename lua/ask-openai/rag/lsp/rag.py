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
    validator.validate()

@attrs.define
class LSPRagQueryResult:
    """ Either return matches OR an error string, nothing else matters."""
    matches: list = []
    error: str | None = None

class LSPResponseErrors:
    NO_RAG_DIR = "No .rag dir"
    CANCELLED = "Client cancelled query"

async def handle_query(args: LSPRagQueryRequest) -> LSPRagQueryResult:
    stopper = create_stopper(args.msg_id)
    try:
        if fs.is_no_rag_dir():
            return LSPRagQueryResult(error=LSPResponseErrors.NO_RAG_DIR)

        # TODO! REVIEW the ASYNC (i.e. for file ops? or other async capable ops)

        # * parse and validate request parameters
        query = args.query
        if query is None or len(query) == 0:
            logger.info("No query provided")
            return LSPRagQueryResult(error="No query provided")

        stopper.throw_if_stopped()  # before starting expensive work too

        matches = await semantic_grep(
            args=args,
            datasets=datasets,
            stopper=stopper,
        )

        return LSPRagQueryResult(matches=matches)
    finally:
        remove_stopper(args.msg_id)

async def update_file_from_pygls_doc(lsp_doc: TextDocument, options: RAGChunkerOptions):
    file_path = Path(lsp_doc.path)

    hash = get_file_hash_from_lines(lsp_doc.lines)

    new_chunks = build_chunks_from_lines(file_path, hash, lsp_doc.lines, options)

    with logger.timer(f"update_file {fs.get_loggable_path(file_path)}"):
        await datasets.update_file(file_path, new_chunks)
