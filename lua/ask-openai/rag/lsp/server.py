import asyncio
import logging
import os
import signal
from pathlib import Path

import lsprotocol.types as types
from pygls import uris
from pygls.lsp.server import LanguageServer
from pygls.protocol.json_rpc import MsgId

from lsp.chunks.chunker import RAGChunkerOptions
from lsp import ignores, rag
from lsp import fs
from lsp.context.imports import imports
from lsp.logs import get_logger, logging_fwk_to_language_server_log_file

logging_fwk_to_language_server_log_file(logging.INFO)
# logging_fwk_to_language_server_log_file(logging.DEBUG)
logger = get_logger(__name__)

server = LanguageServer("ask_language_server", "v0.1")

original__handle_cancel_notification = server.protocol._handle_cancel_notification

def _fix_handle_cancel_notification(msg_id: MsgId):
    """FIXES cancel logic to look at task name to cancel correct future!"""
    # TODO make a PR once you figure out the reason the pop doesn't work in pygls
    #   BUG is this line AFAICT pop is failing:
    #   https://github.com/g0t4/ask-openai.nvim/blob/9ce9d9a8/.venv/lib/python3.12/site-packages/pygls/protocol/json_rpc.py#L344
    # I basically rewrote pop to use get_name to find the future (Task) for msg_id
    #   once cancel is called, if the task was running (marked pending)
    #   then it will throw CancelledError inside (wrap awaits in try/catch and then gracefully stop)
    logger.info(f"attempt cancel {msg_id}")

    for _key, future in server.protocol._request_futures.copy().items():
        if hasattr(future, "get_name"):
            name = future.get_name()
            # logger.info(f'Found matching task by name: {msg_id=} {name} {key=}')
            if name == f"Task-{msg_id}":
                # TODO! check state of task if finished? and don't try cancel if so
                # logger.debug(f'Killing the real task: {msg_id=} {future}')
                if future.cancel():
                    logger.info(f'[bold green]TASK CANCEL RETURNED SUCCESS {msg_id=} {future}')
                    return
                # FYI original _handle_cancel_notification's pop doesn't appear to remove my task, so I am leaving it
                #  also, _send_handler_result is called after cancel... and _send_handler_result calls pop too
                logger.error(f"[bold red] TASK CANCEL NOT SUCCESSFUL  {msg_id=} passed_future:{future}")
                return  # if task found, by name, skip calling original__handle_cancel_notification... in fact it might mess up something else that it cancels instead!!
        # else:
        # logger.debug(f"not targeted task: {key=} {future}")

    logger.error(f"fallback to original__handle_cancel_notification {msg_id}")
    original__handle_cancel_notification(msg_id)

server.protocol._handle_cancel_notification = _fix_handle_cancel_notification

@server.feature(types.INITIALIZE)
def on_initialize(_: LanguageServer, params: types.InitializeParams):
    global dot_rag_dir

    # # PRN use workspace folders if multi-workspace ...
    # #   not sure I'll use this but never know
    # logger.debug(f"{params.workspace_folders=}")
    # server.workspace.folders

    fs.set_root_dir(params.root_path)

    if fs.is_no_rag_dir():
        # DO NOT notify yet, that has to come after server responds to initialize request
        return types.InitializeResult(capabilities=types.ServerCapabilities())

    ignores.use_pygls_workspace(fs.root_path)

def tell_client_to_shut_that_shit_down_now():
    server.protocol.notify("fuu/no_dot_rag__do_the_right_thing_wink")

@server.feature(types.INITIALIZED)
def on_initialized(_: LanguageServer, _params: types.InitializedParams):
    #  FYI server is managed by the client!
    #  client sends initialize request first => waits for server to send InitializeResult
    #    https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialize
    #  then, client sends initialized (this) request => waits for completion
    #    does not send other requests until initialized is done
    #  https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialized

    if fs.is_no_rag_dir():
        # TODO allow building the index from scratch?
        logger.error(f"STOP on_initialize[d] b/c no .rag dir")
        tell_client_to_shut_that_shit_down_now()
        return

    rag.load_model_and_indexes(fs.dot_rag_dir)  # TODO! ASYNC?
    rag.validate_rag_indexes()  # TODO! ASYNC?

async def update_rag_for_text_doc(doc_uri: str):
    if fs.is_no_rag_dir():
        return

    doc_path = uris.to_fs_path(doc_uri)
    if doc_path == None:
        logger.warning(f"abort update rag... to_fs_path returned {doc_path}")
        return
    if ignores.is_ignored(doc_path, server):
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

    doc = server.workspace.get_text_document(doc_uri)  # TODO! async
    if doc is None:
        logger.error(f"abort... doc not found {doc_uri}")
        return
    await rag.update_file_from_pygls_doc(doc, RAGChunkerOptions.ProductionOptions())  # TODO! ASYNC REVIEW

@server.feature(types.TEXT_DOCUMENT_DID_SAVE)
async def doc_saved(params: types.DidSaveTextDocumentParams):
    await update_rag_for_text_doc(params.text_document.uri)

@server.feature(types.TEXT_DOCUMENT_DID_OPEN)
async def doc_opened(params: types.DidOpenTextDocumentParams):
    # imports.on_open(params)
    await update_rag_for_text_doc(params.text_document.uri)

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
async def rag_command_context_related(_: LanguageServer, args: rag.LSPRagQueryRequest) -> rag.LSPRagQueryResult:
    try:
        return await rag.handle_query(args, top_k=50, skip_same_file=False)  # TODO! ASYNC REVIEW
    except asyncio.CancelledError as e:
        # avoid leaving on in logs b/c takes up a ton of space for stack trace
        # logger.info("Client cancelled query", exc_info=e) # uncomment to see where error is raised
        return rag.LSPRagQueryResult(error=rag.LSPResponseErrors.CANCELLED)

@server.command("context.query")
async def rag_command_context_query(_: LanguageServer, args: rag.LSPRagQueryRequest) -> rag.LSPRagQueryResult:
    try:
        return await rag.handle_query(args, skip_same_file=True)
    except asyncio.CancelledError as e:
        return rag.LSPRagQueryResult(error=rag.LSPResponseErrors.CANCELLED)

def sigkill_self_else_pygls_hangs_when_test_standalone_startup_of_LS(*_):
    print("SIGKILL myself")
    os.kill(os.getpid(), signal.SIGKILL)

# TODO detect when LSP disconnects and shutdown self?

signal.signal(signal.SIGINT, sigkill_self_else_pygls_hangs_when_test_standalone_startup_of_LS)

server.start_io()
