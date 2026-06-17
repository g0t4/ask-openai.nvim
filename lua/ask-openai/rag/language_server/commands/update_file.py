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

async def schedule_update(uri: str):
    if uri.endswith("/AskAgent"):
        # PRN move client side
        logger.info("skipping AskAgent")
        return

    if fs.is_no_rag_dir():
        return

    await update_queue.fire_and_forget(uri)

def register_commands(server: LanguageServer):

    @server.feature(types.TEXT_DOCUMENT_DID_SAVE)
    async def doc_saved(params: types.DidSaveTextDocumentParams):
        # logger.info(f"doc_saved {params=}")
        await schedule_update(params.text_document.uri)

    @server.feature(types.TEXT_DOCUMENT_DID_OPEN)
    async def doc_opened(params: types.DidOpenTextDocumentParams):
        # logger.info(f"doc_opened {params=}")
        await schedule_update(params.text_document.uri)

    # @server.feature(types.WORKSPACE_DID_CHANGE_WATCHED_FILES)
    # async def on_watched_files_changed(params: types.DidChangeWatchedFilesParams):
    #     if fs.is_no_rag_dir():
    #         return
    #     #   workspace/didChangeWatchedFiles # when files changed outside of editor... i.e. nvim will detect someone else edited a file in the workspace (another nvim instance, maybe CLI tool, etc)
    #     logger.debug(f"didChangeWatchedFiles: {params}")
    #     # update_rag_file_chunks(params.changes[0].uri)
    #
    # @server.feature(types.TEXT_DOCUMENT_DID_CLOSE)
    # async def doc_closed(params: types.DidCloseTextDocumentParams):
    #     if fs.is_no_rag_dir():
    #         return
    #     logger.pp_debug("didClose", params)
    #     # PRN on didOpen track open files, didClose track closed... use for auto-context!
    #
    # @server.feature(types.TEXT_DOCUMENT_DID_CHANGE)
    # async def doc_changed(params: types.DidChangeTextDocumentParams):
    #     if fs.is_no_rag_dir():
    #         return
    #     # https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didChange
    #     logger.pp_debug("didChange", params)
    #     # FYI would use this to rebuild... but right now doc_saved seems to work fine for updating a file's vectors
