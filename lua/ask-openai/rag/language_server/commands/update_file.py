import asyncio
import lsprotocol.types as types
from pygls.lsp.server import LanguageServer

from rag.logs import get_logger
from index import fs
from language_server.file_queue import FileUpdateEmbeddingsQueue

logger = get_logger(__name__)

update_queue: FileUpdateEmbeddingsQueue

def create_queue(server: LanguageServer):
    global update_queue

    loop = asyncio.get_running_loop()  # btw RuntimeError if no current loop (a good thing)
    # logger.info(f'{loop=} {id(loop)=}')  # sanity check loop used when scheduling

    update_queue = FileUpdateEmbeddingsQueue(fs.get_config(), fs.rag_project.root_path, server, loop)

def register_commands(server: LanguageServer):

    @server.feature(types.TEXT_DOCUMENT_DID_SAVE)
    async def doc_saved(params: types.DidSaveTextDocumentParams):
        # logger.info(f"doc_saved {params=}")
        await schedule_update(params.text_document.uri)

    @server.feature(types.TEXT_DOCUMENT_DID_OPEN)
    async def doc_opened(params: types.DidOpenTextDocumentParams):
        # logger.info(f"doc_opened {params=}")
        await schedule_update(params.text_document.uri)

    async def schedule_update(uri: str):
        if uri.endswith("/AskAgent"):
            # PRN move client side
            logger.info("skipping AskAgent")
            return

        if fs.is_no_rag_dir():
            return

        await update_queue.fire_and_forget(uri)
