from pathlib import Path

import attrs
from pygls.workspace import TextDocument

from chunks.chunker import build_chunks_from_lines, get_file_hash_from_lines, RAGChunkerOptions
from rag.logs import get_logger
from language_server.stoppers import Stopper, create_stopper, remove_stopper
from index.storage import Datasets, load_all_datasets
from inference.client.retrieval import *
from index.validate import DatasetsValidator
from index import fs

logger = get_logger(__name__)

@attrs.define
class LSPSemanticGrepResult:
    """ Either return matches OR an error string, nothing else matters."""
    matches: list = []
    error: str | None = None

class LSPResponseErrors:
    NO_RAG_DIR = "No .rag dir"
    CANCELLED = "Client cancelled query"

async def grep_command(args: LSPSemanticGrepRequest, datasets: Datasets) -> LSPSemanticGrepResult:
    stopper = create_stopper(args.msgId)
    try:
        if fs.is_no_rag_dir():
            return LSPSemanticGrepResult(error=LSPResponseErrors.NO_RAG_DIR)

        # TODO REVIEW ASYNC (i.e. for file ops? or other async capable ops)

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
