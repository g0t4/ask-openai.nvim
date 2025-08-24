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

# FYI v2 pygls supports databinding args... but I had issues with j
@attrs.define
class LSPRagQueryRequest:
    query: str
    currentFileAbsolutePath: str | None = None
    vimFiletype: str | None = None
    instruct: str | None = None
    msg_id: str = ""
    # MAKE SURE TO GIVE DEFAULT VALUES IF NOT REQUIRED

@attrs.define
class LSPRagQueryResult:
    """ Either return matches OR an error string, nothing else matters."""
    matches: list = []
    error: str | None = None

class LSPResponseErrors:
    NO_RAG_DIR = "No .rag dir"
    CANCELLED = "Client cancelled query"

# PRN make top_k configurable (or other params)
async def handle_query(args: LSPRagQueryRequest, top_k=3, skip_same_file=False) -> LSPRagQueryResult:
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

        vim_filetype = args.vimFiletype
        current_file_abs = args.currentFileAbsolutePath
        instruct = args.instruct

        logger.info(f'{args.msg_id=} {query=}: {current_file_abs=} {vim_filetype=} {instruct=}')

        stopper.throw_if_stopped()  # before starting expensive work too

        matches = await semantic_grep(
            query=query,
            instruct=instruct,
            current_file_abs=current_file_abs,
            vim_filetype=vim_filetype,
            skip_same_file=skip_same_file,
            top_k=top_k,
            datasets=datasets,
            msg_id=args.msg_id,
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
