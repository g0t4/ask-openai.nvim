import logging
import os
from pathlib import Path
import signal

import lsprotocol.types as types
from pygls import uris, workspace
from pygls.server import LanguageServer

from lsp.chunks.chunker import RAGChunkerOptions
from lsp import ignores, rag
from lsp import fs
from lsp.context.imports import imports
from lsp.logs import get_logger, logging_fwk_to_language_server_log_file
from typing import Any

logging_fwk_to_language_server_log_file(logging.INFO)
# logging_fwk_to_language_server_log_file(logging.DEBUG)
logger = get_logger(__name__)

server = LanguageServer("ask_language_server", "v0.1")

# original_handle_notification = server.lsp._handle_notification
# original_handle_request = server.lsp._handle_request
#
# def _handle_request(msg_id, method_name, params):
#     logger.info(f'request id: {msg_id}')
#     original_handle_request(msg_id, method_name, params)
#
# def _handle_notification(method_name: str, params: Any):
#     id = params.id if hasattr(params, "id") else "noid"
#     logger.info(f'notification {method_name} {id=}')
#     # if method_name == CANCEL_REQUEST:
#     # self._handle_cancel_notification(params.id)
#     original_handle_notification(method_name, params)
#
# logger.info(server.lsp._handle_notification)
# server.lsp._handle_notification = _handle_notification
# server.lsp._handle_request = _handle_request

@server.feature(types.INITIALIZE)
def on_initialize(_: LanguageServer, params: types.InitializeParams):
    global dot_rag_dir
    # TODO!ASYNC

    # # PRN use workspace folders if multi-workspace ...
    # #   not sure I'll use this but never know
    # logger.debug(f"{params.workspace_folders=}")
    # server.workspace.folders

    fs.set_root_dir(params.root_path)

    if fs.is_no_rag_dir():
        # TODO allow building the index from scratch?
        # DO NOT notify yet, that has to come after server responds to initialize request
        return types.InitializeResult(capabilities=types.ServerCapabilities())

    ignores.use_pygls_workspace(fs.root_path)

def tell_client_to_shut_that_shit_down_now():
    server.send_notification("fuu/no_dot_rag__do_the_right_thing_wink")

# @server.feature(types.CANCEL_REQUEST)
# async def on_request_cancel(_: LanguageServer, _params: types.CancelParams):
#     # I am not sure I even need this.. pygls should handle canceling non-started work
#     #  + it should help cooperatively stop in progress, async tasks
#     logger.error(f"CANCEL REQUESTED for {_params.id=}")

@server.feature(types.INITIALIZED)
def on_initialized(_: LanguageServer, _params: types.InitializedParams):
    #  FYI server is managed by the client!
    #  client sends initialize request first => waits for server to send InitializeResult
    #    https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialize
    #  then, client sends initialized (this) request => waits for completion
    #    does not send other requests until initialized is done
    #  https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialized
    # TODO!ASYNC to avoid blocking initial requests that don't depend on what I am initializing here

    # server.show_message(f"server message foo", types.MessageType.Warning)
    # server.show_message_log("server log message bar", types.MessageType.Error)
    if fs.is_no_rag_dir():
        # TODO allow building the index from scratch?
        logger.error(f"STOP on_initialize[d] b/c no .rag dir")
        tell_client_to_shut_that_shit_down_now()
        return

    rag.load_model_and_indexes(fs.dot_rag_dir)

    # FYI I took out the part that preloads numpy when LSP starts up... I am going to leave it off for now... just reminder when you asyncify startup too
    #   that you should consider optimizing startup (i.e. imports) on startup for fastest user experience
    #   that might mean pre-loading some deps that are going to be used so they're ready for users that don't initially need anything but later want fast first LSP request experience
    #   for users that want immediate LSP requests... it won't matter if its in initialize (here) or just when their first request comes in
    # import numpy   # used to happen in model_wrapper back when I had that for diff models.. this was all that was left after moving the rest to inference server

    rag.validate_rag_indexes()

def update_rag_for_text_doc(doc_uri: str):
    # TODO!ASYNC
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

    doc = server.workspace.get_text_document(doc_uri)
    if doc is None:
        logger.error(f"abort... doc not found {doc_uri}")
        return
    rag.update_file_from_pygls_doc(doc, RAGChunkerOptions.ProductionOptions())

@server.feature(types.TEXT_DOCUMENT_DID_SAVE)
def doc_saved(params: types.DidSaveTextDocumentParams):
    if fs.is_no_rag_dir():
        # TODO check langauge_extension too? for all handlers that work with doc uri? or let it fail normally in processing the request?
        return
    # TODO!ASYNC

    logger.pp_debug("didSave", params)
    update_rag_for_text_doc(params.text_document.uri)

# @server.feature(types.WORKSPACE_DID_CHANGE_WATCHED_FILES)
# async def on_watched_files_changed(params: types.DidChangeWatchedFilesParams):
#     if fs.is_no_rag_dir():
#         return
#     #   workspace/didChangeWatchedFiles # when files changed outside of editor... i.e. nvim will detect someone else edited a file in the workspace (another nvim instance, maybe CLI tool, etc)
#     logger.debug(f"didChangeWatchedFiles: {params}")
#     # TODO is this one or more events? do I need to uniqify?
#     # update_rag_file_chunks(params.changes[0].uri)

# UNREGISTER WHILE NOT USING:
@server.feature(types.TEXT_DOCUMENT_DID_OPEN)
def doc_opened(params: types.DidOpenTextDocumentParams):
    if fs.is_no_rag_dir():
        return
    logger.pp_debug("didOpen", params)

    #  ! on didOpen track open files, didClose track closed... so you always KNOW WHAT IS OPEN!!!

    # imports.on_open(params) # WIP
    # TODO!ASYNC

    # * FYI this was just for quick testing to avoid needing a save or otherwise (just restart nvim)
    # ONLY do this b/c right now I don't rebuild the entire dataset until manually (eventually git commit, later can update here to disk)
    update_rag_for_text_doc(params.text_document.uri)

# @server.feature(types.TEXT_DOCUMENT_DID_CLOSE)
# async def doc_closed(params: types.DidCloseTextDocumentParams):
#     if fs.is_no_rag_dir():
#         return
#     logger.pp_debug("didClose", params)
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
async def rag_command_context_related(_: LanguageServer, params: types.ExecuteCommandParams):
    if fs.is_no_rag_dir():
        return

    if params is None or params[0] is None:
        logger.error(f"aborting semantic_grep b/c missing params {params}")
        return
    # TODO!ASYNC

    message = params[0]
    logger.info("semantic_grep handler")
    return await rag.handle_query(message, 50, skip_same_file=False)

@server.command("context.query")
async def rag_command_context_query(_: LanguageServer, params: types.ExecuteCommandParams):
    if fs.is_no_rag_dir():
        return

    if params is None or params[0] is None:
        logger.error(f"aborting context.query b/c missing params {params}")
        return
    # TODO!ASYNC

    message = params[0]
    return await rag.handle_query(message, skip_same_file=True)

# how can I intercept shutdown from client?
#
# @server.feature(types.SHUTDOWN)
# def on_shutdown(_: LanguageServer):
#     logger.debug(f"shutting down")
#     # os._exit(0)
#
# @server.feature(types.EXIT)
# def on_exit(_: LanguageServer):
#     logger.debug(f"exiting")
#     # os._exit(0)

def sigkill_self_else_pygls_hangs_when_test_standalone_startup_of_LS(*_):
    print("SIGKILL myself")
    os.kill(os.getpid(), signal.SIGKILL)

# TODO how can I detect if client disconnects?
#   if I start nvim before server is initialized then it gets orphaned (have to kill it)
#

signal.signal(signal.SIGINT, sigkill_self_else_pygls_hangs_when_test_standalone_startup_of_LS)

server.start_io()
