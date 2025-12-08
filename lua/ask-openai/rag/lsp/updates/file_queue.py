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

logger = get_logger(__name__)

class FileUpdateQueue:

    def __init__(self, config: Config, server: LanguageServer, loop: asyncio.AbstractEventLoop, debounce_sec=0.3):
        self.debounce_sec = debounce_sec
        self.streams = {}  # uri -> Subject()
        self.tasks: dict[str, asyncio.Task] = {}  # uri -> current asyncio.Task
        self.config = config
        self.server = server
        self.loop = loop

    def _get_stream(self, uri):
        if uri not in self.streams:
            subj = Subject()
            self.streams[uri] = subj

            subj.pipe(
                ops.debounce(self.debounce_sec),  # strictly not necessary b/c work can be canceled too... but it won't hurt either and will save my server from thrashing between repeated saves back to back (don't even start in that case)
            ).subscribe(lambda item: self._schedule(uri))

        return self.streams[uri]

    def push(self, uri: str):
        """Push an update event for a file (fire-and-forget)."""
        self._get_stream(uri).on_next({})  # no event details, will lookup doc when callback runs

    def _schedule(self, uri):
        """Cancel stale work, schedule new async job."""
        logger.info(f"_schedule' {uri}")

        old = self.tasks.get(uri)
        logger.info(f"old task {old}")
        if old and not old.done():
            logger.info(f"{old.done()=}")
            old.cancel()  # TODO setup cooperative cancellation?

        task = self.loop.create_task(self._worker(uri))
        self.tasks[uri] = task

    async def _worker(self, uri):

        logger.info(f"_worker' {uri}")
        try:
            await self.update_rag_for_text_doc(uri)
        except asyncio.CancelledError:
            logger.debug(f"update cancelled for {uri}")  # TODO comment out once happy its working
            pass
        except Exception as exc:
            print(f"[update error] {uri}: {exc}")

    async def update_rag_for_text_doc(self, doc_uri: str):
        doc_path = uris.to_fs_path(doc_uri)
        if doc_path == None:
            logger.warning(f"abort update rag... to_fs_path returned {doc_path}")
            return

        if not self.config.is_file_type_supported(doc_path):
            logger.debug(f"filetype not supported: {doc_path}")
            return
        if ignores.is_ignored(doc_path, self.server):
            logger.debug(f"rag ignored doc: {doc_path}")
            return
        if Path(doc_path).suffix == "":
            #  i.e. githooks
            # currently I don't index extensionless anwyways, so skip for now in updates
            # would need to pass vim_filetype from client (like I do for FIM queries within them)
            #   alternatively I could parse shebang?
            # but, I want to avoid extensionless so lets not make it possible to use them easily :)
            logger.info(f"skip extensionless files {doc_path}")
            return

        doc = self.server.workspace.get_text_document(doc_uri)
        if doc is None:
            logger.error(f"abort... doc not found {doc_uri}")
            return
        await rag.update_file_from_pygls_doc(doc, RAGChunkerOptions.ProductionOptions())  # TODO! ASYNC REVIEW
