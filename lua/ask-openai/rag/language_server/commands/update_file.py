import asyncio
import lsprotocol.types as types
from pathlib import Path
from pygls import uris
from pygls.lsp.server import LanguageServer
from pygls.workspace import TextDocument
from rx import operators as ops
from rx.subject.subject import Subject

from chunks.chunker import RAGChunkerOptions, build_chunks_from_lines, get_file_hash_from_lines
from config import RagConfig
from config.domains import resolve_semantic_domain
from index import ignores, workspace
from index.storage import Datasets
from language_server import rag
from logs import get_logger

logger = get_logger(__name__)

class FileUpdateEmbeddingsQueue:

    def __init__(
        self,
        config: RagConfig,
        root_path: Path,
        server: LanguageServer,
        loop: asyncio.AbstractEventLoop,
        debounce_sec=0.3,
    ):
        self.debounce_sec = debounce_sec
        self.uri_subjects = {}  # uri -> Subject()
        self.tasks: dict[str, asyncio.Task] = {}  # uri -> current asyncio.Task
        self.config = config
        self.server = server
        self.loop = loop
        self.root_path = root_path

    async def fire_and_forget(self, uri: str):
        # * BTW best way to test this... open LS logs and then ctrl-s in a doc repeatedly, should only see update after last save (depending on debounce interval)
        #    or yeah, change debounce interval and see if it takes a while but does update

        def get_uri_subject():
            if uri in self.uri_subjects:
                return self.uri_subjects[uri]

            subject = Subject()
            self.uri_subjects[uri] = subject
            subject.pipe(
                ops.debounce(self.debounce_sec),  # strictly not necessary b/c work can be canceled too... but it won't hurt either and will save my server from thrashing between repeated saves back to back (don't even start in that case)
            ).subscribe(lambda item: self._schedule_onto_asyncio_loop(uri))
            return subject

        get_uri_subject().on_next({})  # empty event, b/c closure has uri (above)

    def _schedule_onto_asyncio_loop(self, uri):
        # Use loop.call_soon_threadsafe to schedule the coroutine (`_schedule` in this case) from another thread.
        # create_task only creates the task; it won’t start until the event loop runs,
        # and RxPY callbacks execute outside the asyncio loop,
        # so we must safely push the coroutine onto the loop to both create the task and make sure the new task runs
        #  else last update to embeddings won't run until something else triggers event loop!
        self.loop.call_soon_threadsafe(self._schedule, uri)

    def _schedule(self, uri):
        # logger.info(f"_schedule: {uri}")

        # * cancel outstanding update
        old = self.tasks.get(uri)
        if old and not old.done():
            # FYI currently no cooperative cancellation
            # - this is mostly about stopping a task that is not yet started
            logger.info(f"old task is NOT done: {old}")
            old.cancel()

        task = self.loop.create_task(self._embeddings_worker(uri))
        self.tasks[uri] = task

    async def _embeddings_worker(self, uri):
        # logger.info(f"_embeddings_worker started {uri}")
        try:
            await self.update_embeddings(uri)
        except asyncio.CancelledError:
            logger.debug(f"update cancelled for {uri}")  # TODO comment out once happy its working
        except Exception as exc:
            logger.error(f"[update error] {uri}: {exc}")

    async def update_embeddings(self, doc_uri: str):
        doc_path = uris.to_fs_path(doc_uri)
        if doc_path is None:
            logger.warning(f"abort update rag... to_fs_path returned {doc_path}")
            return

        if ignores.is_file_ignored_allchecks(doc_path, self.config, self.root_path):
            logger.debug(f"rag ignored doc: {doc_path}")
            return

        domain = resolve_semantic_domain(doc_path)
        if domain is None:
            logger.info(f"skip unresolved semantic domain: {doc_path}")
            return

        doc = self.server.workspace.get_text_document(doc_uri)
        if doc is None:
            logger.error(f"abort... doc not found {doc_uri}")
            return
        # TODO eventually don't get datasets from rag module?
        await update_file_from_pygls_doc(doc, RAGChunkerOptions.ProductionOptions(), rag.datasets)

async def update_file_from_pygls_doc(lsp_doc: TextDocument, options: RAGChunkerOptions, _passed_datasets: Datasets):
    file_path = Path(lsp_doc.path)

    with logger.timer(f"update_file {workspace.get_loggable_path(file_path)}"):
        hash = get_file_hash_from_lines(lsp_doc.lines)
        # FYI you can check hash for changes, but remember this is off of disk and you only update that on commit
        #   so really there's no point to ask if changed, b/c only going to be saving materially if altering it
        #   in which case it's always gonna look altered at least LS side
        new_chunks = build_chunks_from_lines(file_path, hash, lsp_doc.lines, options)  # PRN await
        await _passed_datasets.update_file(file_path, new_chunks)

update_queue: FileUpdateEmbeddingsQueue

def create_queue(server: LanguageServer):
    global update_queue

    loop = asyncio.get_running_loop()  # btw RuntimeError if no current loop (a good thing)
    # logger.info(f'{loop=} {id(loop)=}')  # sanity check loop used when scheduling

    update_queue = FileUpdateEmbeddingsQueue(workspace.get_config(), workspace.rag_project.root_path, server, loop)

async def schedule_update(uri: str):
    if uri.endswith("/AskAgent"):
        # PRN move client side
        logger.info("skipping AskAgent")
        return

    if workspace.is_no_rag_dir():
        return

    await update_queue.fire_and_forget(uri)

def setup(server: LanguageServer):

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
    #     if workspace.is_no_rag_dir():
    #         return
    #     #   workspace/didChangeWatchedFiles # when files changed outside of editor... i.e. nvim will detect someone else edited a file in the workspace (another nvim instance, maybe CLI tool, etc)
    #     logger.debug(f"didChangeWatchedFiles: {params}")
    #     # update_rag_file_chunks(params.changes[0].uri)
    #
    # @server.feature(types.TEXT_DOCUMENT_DID_CLOSE)
    # async def doc_closed(params: types.DidCloseTextDocumentParams):
    #     if workspace.is_no_rag_dir():
    #         return
    #     logger.pp_debug("didClose", params)
    #     # PRN on didOpen track open files, didClose track closed... use for auto-context!
    #
    # @server.feature(types.TEXT_DOCUMENT_DID_CHANGE)
    # async def doc_changed(params: types.DidChangeTextDocumentParams):
    #     if workspace.is_no_rag_dir():
    #         return
    #     # https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didChange
    #     logger.pp_debug("didChange", params)
    #     # FYI would use this to rebuild... but right now doc_saved seems to work fine for updating a file's vectors
