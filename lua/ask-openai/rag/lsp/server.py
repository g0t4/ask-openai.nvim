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

server = LanguageServer("ask_language_server", "v0.1")

@server.feature(types.INITIALIZE)
def on_initialize(ls: LanguageServer, params: types.InitializeParams):
    global root_fs_path
    root_uri = params.root_uri  # ., root_uri='file:///Users/wesdemos/repos/github/g0t4/ask-openai.nvim'
    if root_uri is None:
        logging.error(f"aborting on_initialize b/c missing client workspace root_uri {root_uri}")
        raise ValueError("root_uri is None")
    logging.info(f"root_uri {root_uri}")
    fs_path = uris.to_fs_path(root_uri)
    if fs_path is None:
        logging.error(f"aborting on_initialize b/c missing client workspace fspath {fs_path}")
        raise ValueError("fspath is None")
    root_fs_path = Path(fs_path)
    logging.info(f"fspath {root_fs_path}")

@server.feature(types.INITIALIZED)
def on_initialized(server):
    #  FYI server is managed by the client!
    #  client sends initialize request first => waits for server to send InitializeResult
    #    https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialize
    #  then, client sends initialized (this) request => waits for completion
    #    does not send other requests until initialized is done
    #  https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialized
    rag.load_model_and_indexes(root_fs_path)

@server.feature(types.TEXT_DOCUMENT_DID_OPEN)
def doc_opened(params: types.DidOpenTextDocumentParams):
    # FYI just for testing purposes
    logging.info(f"didOpen: {params}")

@server.feature(types.TEXT_DOCUMENT_DID_CHANGE)
def doc_changed(params: types.DidChangeTextDocumentParams):
    # https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didChange
    logging.info(f"didChange: {params}")

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

@server.command("ask.rag.fim.query")
def rag_query(ls: LanguageServer, params: ExecuteCommandParams):
    if params is None or params[0] is None:
        logging.error(f"aborting ask.rag.fim.query b/c missing params {params}")
        return

    # PRN cache last N rag queries? would help to regen another completion but maybe not that common?

    args = params[0]
    logging.info("Query: %s", args)
    return rag.handle_query(args)

server.start_io()
