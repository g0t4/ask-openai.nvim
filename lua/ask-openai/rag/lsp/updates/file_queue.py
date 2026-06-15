import asyncio
import logging

from pathlib import Path
from pygls import uris
from pygls.lsp.server import LanguageServer
from rx import operators as ops
from rx.subject.subject import Subject

from lsp.config import Config
from lsp.chunks.chunker import RAGChunkerOptions
from lsp.logs import get_logger
from lsp import ignores, rag
from lsp.filetypes import resolve_filetype

logger = get_logger(__name__)


class FileUpdateEmbeddingsQueue:

    def __init__(
        self,
        config: Config,
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

        if ignores.is_ignored_allchecks(doc_path, self.config, self.root_path):
            logger.debug(f"rag ignored doc: {doc_path}")
            return

        # Resolve filetype through the three-layer mapper (extension → filename → shebang)
        filetype = resolve_filetype(doc_path)
        if filetype is None:
            logger.info(f"skip unresolved file (no extension, no known filename, no shebang): {doc_path}")
            return

        doc = self.server.workspace.get_text_document(doc_uri)
        if doc is None:
            logger.error(f"abort... doc not found {doc_uri}")
            return
        await rag.update_file_from_pygls_doc(doc, RAGChunkerOptions.ProductionOptions())
