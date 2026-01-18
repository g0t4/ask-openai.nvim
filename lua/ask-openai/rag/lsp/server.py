import asyncio
import logging
import os
import signal
from pathlib import Path

import lsprotocol.types as types
from pygls.lsp.server import LanguageServer
from pygls.protocol.json_rpc import MsgId

from lsp import fs
from lsp import ignores, rag
from lsp.chunks.chunker import RAGChunkerOptions
from lsp.context.imports import imports
from lsp.logs import get_logger, logging_fwk_to_language_server_log_file, disable_printtmp
from lsp.updates.file_queue import FileUpdateEmbeddingsQueue

disable_printtmp()  # LSP uses STDOUT for comms!

from lsp.stoppers import request_stop, create_stopper, remove_stopper

logging_fwk_to_language_server_log_file(logging.INFO)
# logging_fwk_to_language_server_log_file(logging.DEBUG)
logger = get_logger(__name__)

server = LanguageServer("ask_language_server", "v0.1")

original__handle_cancel_notification = server.protocol._handle_cancel_notification

def _trigger_stopper_on_cancel(msg_id: MsgId):
    if request_stop(msg_id):
        logger.info(f'triggered stopper {msg_id=}')
        return

    # logger.info(f"fallback to original__handle_cancel_notification {msg_id}")
    original__handle_cancel_notification(msg_id)

server.protocol._handle_cancel_notification = _trigger_stopper_on_cancel

@server.command("SLEEPY")
async def sleepy(_ls: LanguageServer, args: dict):
    msg_id = _ls.protocol.msg_id  # workaround to load msg_id via contextvars
    logger.info(f"sleepy started {msg_id=}")
    stopper = create_stopper(msg_id)

    try:
        for i in range(10):
            stopper.throw_if_stopped()

            async with asyncio.TaskGroup() as tg:
                job = tg.create_task(asyncio.sleep(3))
                stop_requested = tg.create_task(stopper.wait())
                done, pending = await asyncio.wait(
                    [job, stop_requested],
                    return_when=asyncio.FIRST_COMPLETED,
                )
                if stop_requested in done:
                    # Raising inside the TG cancels/awaits other tasks
                    stopper.throw_if_stopped()

                stop_requested.cancel()  # cleanup

            logger.info(f"ping {msg_id=} {i}")

        return {"status": "done", "msg_id": msg_id}
    except asyncio.CancelledError as e:
        logger.info(f"KILLED {msg_id=}")  #, exc_info=e)
        return {"status": "canelled", "msg_id": msg_id}
    finally:
        remove_stopper(msg_id)

@server.feature(types.INITIALIZE)
def on_initialize(_: LanguageServer, params: types.InitializeParams):
    global dot_rag_dir, config

    # # PRN use workspace folders if multi-workspace ...
    # # FYI could also get me CWD, round about way, if I wanted to prioritize that for .rag dir over git repo root
    # logger.info(f"{params.workspace_folders=}")
    # server.workspace.folders

    fs.set_root_dir(params.root_path)
    config = fs.get_config()
    if not config.enabled or fs.is_no_rag_dir():
        # DO NOT notify yet, that has to come after server responds to initialize request
        return types.InitializeResult(capabilities=types.ServerCapabilities())

def tell_client_to_shut_that_shit_down_now():
    server.protocol.notify("fuu/no_dot_rag__do_the_right_thing_wink")

update_queue: FileUpdateEmbeddingsQueue

@server.feature(types.INITIALIZED)
def on_initialized(_: LanguageServer, _params: types.InitializedParams):
    global update_queue
    #  FYI server is managed by the client!
    #  client sends initialize request first => waits for server to send InitializeResult
    #    https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialize
    #  then, client sends initialized (this) request => waits for completion
    #    does not send other requests until initialized is done
    #  https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialized

    if not config.enabled:
        logger.info("RAG disabled, notifying LSP client to shutdown")
        tell_client_to_shut_that_shit_down_now()
        return

    if fs.is_no_rag_dir():
        # TODO allow building the index from scratch?
        logger.error(f"STOP on_initialize[d] b/c no .rag dir")
        tell_client_to_shut_that_shit_down_now()
        return

    rag.load_model_and_indexes(fs.dot_rag_dir)  # TODO! ASYNC?
    rag.validate_rag_indexes()  # TODO! ASYNC?

    ignores.use_pygls_workspace(fs.root_path)

    loop = asyncio.get_running_loop()  # btw RuntimeError if no current loop (a good thing)
    # logger.info(f'{loop=} {id(loop)=}')  # sanity check loop used when scheduling
    update_queue = FileUpdateEmbeddingsQueue(config, server, loop)

@server.feature(types.TEXT_DOCUMENT_DID_SAVE)
async def doc_saved(params: types.DidSaveTextDocumentParams):
    uri = params.text_document.uri
    # logger.info(f"doc_saved {params=}")
    # logger.info(f"doc_saved {uri}")
    await schedule_update(uri)

@server.feature(types.TEXT_DOCUMENT_DID_OPEN)
async def doc_opened(params: types.DidOpenTextDocumentParams):
    uri = params.text_document.uri
    # logger.info(f"doc_opened {params=}")
    # logger.info(f"doc_opened {uri}")
    await schedule_update(uri)
    # imports.on_open(params)

async def schedule_update(doc_uri: str):
    if fs.is_no_rag_dir():
        return
    await update_queue.fire_and_forget(doc_uri)

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
#     # FYI would use this to invalidate internal caches and rebuild for a given file, i.e. imports, RAG vectors, etc
#     #   rebuild on git commit + incremental updates s/b super fast?

@server.command("semantic_grep")
async def semantic_grep_command(_: LanguageServer, args: rag.LSPSemanticGrepRequest) -> rag.LSPSemanticGrepResult:
    args.msgId = server.protocol.msg_id
    try:
        return await rag.handle_semantic_grep_ls_command(args)  # TODO! ASYNC REVIEW
    except asyncio.CancelledError as e:
        # avoid leaving on in logs b/c takes up a ton of space for stack trace
        logger.info(f"Client cancelled semantic_grep query {args.msgId=}")  #, exc_info=e)  # uncomment to see where error is raised
        return rag.LSPSemanticGrepResult(error=rag.LSPResponseErrors.CANCELLED)

def sigkill_self_else_pygls_hangs_when_test_standalone_startup_of_LS(*_):
    logger.warn("SIGKILL myself")
    os.kill(os.getpid(), signal.SIGKILL)

# TODO detect when LSP disconnects and shutdown self?

signal.signal(signal.SIGINT, sigkill_self_else_pygls_hangs_when_test_standalone_startup_of_LS)

server.start_io()
