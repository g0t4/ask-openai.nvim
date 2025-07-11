import os
from pathlib import Path
import signal

import lsprotocol.types as types
from pygls import uris, workspace
from pygls.server import LanguageServer

from lsp import imports, rag, ignores
from .logs import get_logger, use_lang_server_logs

# BTW, cd to `rag` dir and => `python3 -m lsp.server` to test this w/o nvim, make sure it starts up at least

# logger_name = __name__ if __name__ != "__main__" else "lsp-server" # PRN don't use __main__?
use_lang_server_logs()
logger = get_logger(__name__)

server = LanguageServer("ask_language_server", "v0.1")

@server.feature(types.INITIALIZE)
def on_initialize(_: LanguageServer, params: types.InitializeParams):
    global dot_rag_dir

    # # PRN use workspace folders if multi-workspace ...
    # #   not sure I'll use this but never know
    # logger.info(f"{params.workspace_folders=}")
    # server.workspace.folders

    root_path = params.root_path  # ., root_uri='file:///Users/wesdemos/repos/github/g0t4/ask-openai.nvim'
    logger.info(f"workspace {root_path=}")
    if root_path is None:
        logger.error(f"aborting on_initialize b/c missing client workspace root_uri {root_path}")
        raise ValueError("root_uri is None")

    dot_rag_dir = Path(root_path) / ".rag"
    logger.info(f"{dot_rag_dir=}")

    ignores.use_pygls_workspace(root_path)

@server.feature(types.INITIALIZED)
def on_initialized(_: LanguageServer, _params: types.InitializedParams):
    #  FYI server is managed by the client!
    #  client sends initialize request first => waits for server to send InitializeResult
    #    https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialize
    #  then, client sends initialized (this) request => waits for completion
    #    does not send other requests until initialized is done
    #  https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialized
    rag.load_model_and_indexes(dot_rag_dir)

def update_rag_for_text_doc(doc_uri: str):
    doc_path = uris.to_fs_path(doc_uri)
    if doc_path == None:
        logger.warning(f"abort update rag... to_fs_path returned {doc_path=}")
        return
    if ignores.is_ignored(doc_path):
        logger.info(f"rag ignored doc: {doc_path=}")
        return

    doc = server.workspace.get_document(doc_uri)
    if doc is None:
        logger.error(f"abort... doc not found {doc_uri}")
        return
    # logger.info(f'{doc.filename=}')
    # logger.info(f'{doc.path=}')
    # logger.info(f'{doc.language_id=}')
    # logger.info(f'{doc.uri=}')
    rag.update_file_from_pygls_doc(doc)

@server.feature(types.TEXT_DOCUMENT_DID_SAVE)
def doc_saved(params: types.DidSaveTextDocumentParams):
    logger.pp_info("didSave", params)
    update_rag_for_text_doc(params.text_document.uri)

@server.feature(types.WORKSPACE_DID_CHANGE_WATCHED_FILES)
def on_watched_files_changed(params: types.DidChangeWatchedFilesParams):
    #   workspace/didChangeWatchedFiles # when files changed outside of editor... i.e. nvim will detect someone else edited a file in the workspace (another nvim instance, maybe CLI tool, etc)
    logger.info(f"didChangeWatchedFiles: {params}")
    # TODO is this one or more events? do I need to uniqify?
    # update_rag_file_chunks(params.changes[0].uri)

# UNREGISTER WHILE NOT USING:
@server.feature(types.TEXT_DOCUMENT_DID_OPEN)
def doc_opened(params: types.DidOpenTextDocumentParams):
    logger.pp_info("didOpen", params)

    # imports.on_open(params) # WIP

    # * FYI this was just for quick testing to avoid needing a save or otherwise (just restart nvim)
    # ONLY do this b/c right now I don't rebuild the entire dataset until manually (eventually git commit, later can update here to disk)
    update_rag_for_text_doc(params.text_document.uri)

# @server.feature(types.TEXT_DOCUMENT_DID_CHANGE)
def doc_changed(params: types.DidChangeTextDocumentParams):
    # https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didChange
    logger.pp_info("didChange", params)
    # FYI would use this to invalidate internal caches and rebuild for a given file, i.e. imports, RAG vectors, etc
    #   rebuild on git commit + incremental updates s/b super fast?

# @server.feature(types.TEXT_DOCUMENT_COMPLETION)
def completions(params: types.CompletionParams):
    # FYI this is just for initial testing, ok to nuke as I have no plans for completions support
    items = []
    document: workspace.TextDocument = server.workspace.get_document(params.text_document.uri)
    current_line = document.lines[params.position.line].strip()
    # if current_line.endswith("hello."):
    items = [
        types.CompletionItem(label="world"),
        types.CompletionItem(label="friend"),
    ]
    return types.CompletionList(is_incomplete=False, items=items)

# !!!  MAKE THIS A CONTEXT LS... NOT JUST RAG!!!!
@server.command("ask.context.query")
def context_query(params: types.ExecuteCommandParams):
    #  ! on didOpen and didChange => hunt imports! (if changed) and cache the list for this file
    #  ! on didOpen track open files, didClose track closed... so you always KNOW WHAT IS OPEN!!!
    #
    # if params is None or params[0] is None:
    #     logger.error(f"aborting ask.context.query b/c missing params {params}")
    #     return
    # args = params[0]
    logger.info("ask.context.query: %s", params)
    # return rag.handle_query(args)
    raise RuntimeError("Not Implemented!")

@server.command("ask.rag.fim.query")
def rag_query(_: LanguageServer, params: types.ExecuteCommandParams):
    if params is None or params[0] is None:
        logger.error(f"aborting ask.rag.fim.query b/c missing params {params}")
        return

    message = params[0]
    return rag.handle_query(message)

def sigkill_self_else_pygls_hangs_when_test_standalone_startup_of_LS(*_):
    print("SIGKILL myself")
    os.kill(os.getpid(), signal.SIGKILL)

# TODO how can I detect if client disconnects?
#   if I start nvim before server is initialized then it gets orphaned (have to kill it)
#

signal.signal(signal.SIGINT, sigkill_self_else_pygls_hangs_when_test_standalone_startup_of_LS)

server.start_io()
