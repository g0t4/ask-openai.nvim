from pathlib import Path

from lsprotocol.types import (
    CompletionItem,
    CompletionList,
    CompletionParams,
    ExecuteCommandParams,
)
import lsprotocol.types as types
from pygls.server import LanguageServer

from lsp import rag
from pygls import uris

from .logs import logging

logger = logging.getLogger("ask-rag")

server = LanguageServer("ask_language_server", "v0.1")

@server.feature(types.INITIALIZE)
def on_initialize(ls: LanguageServer, params: types.InitializeParams):
    global root_fs_path
    root_uri = params.root_uri  # ., root_uri='file:///Users/wesdemos/repos/github/g0t4/ask-openai.nvim'
    if root_uri is None:
        logger.error(f"aborting on_initialize b/c missing client workspace root_uri {root_uri}")
        raise ValueError("root_uri is None")
    logger.info(f"root_uri {root_uri}")
    fs_path = uris.to_fs_path(root_uri)
    if fs_path is None:
        logger.error(f"aborting on_initialize b/c missing client workspace fspath {fs_path}")
        raise ValueError("fspath is None")
    root_fs_path = Path(fs_path)
    logger.info(f"fspath {root_fs_path}")

@server.feature(types.INITIALIZED)
def on_initialized(server):
    #  FYI server is managed by the client!
    #  client sends initialize request first => waits for server to send InitializeResult
    #    https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialize
    #  then, client sends initialized (this) request => waits for completion
    #    does not send other requests until initialized is done
    #  https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialized
    rag.load_model_and_indexes(root_fs_path)

# TODO!!!! :
@server.feature(types.TEXT_DOCUMENT_DID_SAVE)
def doc_saved(params: types.DidSaveTextDocumentParams):
    logger.info(f"didSave: {params}")

@server.feature(types.WORKSPACE_DID_CHANGE_WATCHED_FILES)
def on_watched_files_changed(params: types.DidChangeWatchedFilesParams):
    #   workspace/didChangeWatchedFiles # when files changed outside of editor... i.e. nvim will detect someone else edited a file in the workspace (another nvim instance, maybe CLI tool, etc)
    logger.info(f"didChangeWatchedFiles: {params}")

#   # didOpen/Close are for real time change basically which I don't need, at least not for RAG (not yet?)

@server.feature(types.TEXT_DOCUMENT_DID_OPEN)
def doc_opened(params: types.DidOpenTextDocumentParams):
    # FYI just for testing purposes
    logger.info(f"didOpen: {params}")

# @server.feature(types.TEXT_DOCUMENT_DID_CHANGE)
# def doc_changed(params: types.DidChangeTextDocumentParams):
#     # https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didChange
#     logger.info(f"didChange: {params}")
#     # TODO is this the only event? is this the right one?
#     #  TODO what if I want to update the actual store? maybe I should have one process for that globally?
#     #   FYI should not run "in-band" with the current RAG query (if any)... just let the current index serve current requests... not likely gonna be much different anyways! esp if just typing chars!
#     # TODO! on LSP events for files, rebuild that one file's chunks and update in-memory index... that way I can avoid thinking about synchronization between multiple app instances?
#     #   rebuild on git commit + incremental updates s/b super fast

@server.feature(types.TEXT_DOCUMENT_COMPLETION)
def completions(params: CompletionParams):
    # FYI this is just for initial testing, ok to nuke as I have no plans for completions support
    items = []
    document = server.workspace.get_document(params.text_document.uri)
    current_line = document.lines[params.position.line].strip()
    # if current_line.endswith("hello."):
    items = [
        CompletionItem(label="world"),
        CompletionItem(label="friend"),
    ]
    return CompletionList(is_incomplete=False, items=items)

# !!!  MAKE THIS A CONTEXT LS... NOT JUST RAG!!!!
@server.command("ask.context.query")
def context_query(params: ExecuteCommandParams):
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
def rag_query(ls: LanguageServer, params: ExecuteCommandParams):
    if params is None or params[0] is None:
        logger.error(f"aborting ask.rag.fim.query b/c missing params {params}")
        return

    # PRN cache last N rag queries? would help to regen another completion but maybe not that common?

    args = params[0]
    logger.info("Query: %s", args)
    return rag.handle_query(args)

server.start_io()
