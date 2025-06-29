# := vim.lsp.get_log_path()
# tail -F ~/.local/state/nvim/lsp.log

#
# v1 migration:
#   https://pygls.readthedocs.io/en/latest/pygls/howto/migrate-to-v1.html
# FYI guides have v2 examples already... ugh
import os
from pygls.server import LanguageServer
from lsprotocol.types import (
    TEXT_DOCUMENT_COMPLETION,
    CompletionItem,
    CompletionList,
    CompletionParams,
    ExecuteCommandParams,
)

import rag
from logs import logging, LogTimer

server = LanguageServer("ask_language_server", "v0.1")

# @server.feature('initialize')
# def on_initialize(ls: LanguageServer, params: dict):
#     logging.info("on_initialize")
#     IIUC I have to build the InitializeResult then if I add this hook... though completions continue to work w/o me doing that here

@server.feature('initialized')
def on_initialized(server):
    #  FYI server is managed by the client!
    #  client sends initialize request first => waits for server to send InitializeResult
    #    https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialize
    #  then, client sends initialized (this) request => waits for completion
    #    does not send other requests until initialized is done
    #  https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialized
    logging.info("on_initialized")
    rag.load_model()

@server.feature(TEXT_DOCUMENT_COMPLETION)
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

@server.command("ask.ragQuery")
def rag_query(ls: LanguageServer, params: ExecuteCommandParams):
    if params is None or params[0] is None:
        logging.error(f"aborting ask.ragQuery b/c missing params {params}")
        return

    args = params[0]
    logging.info("Query: %s", args)
    return rag.handle_query(args)

server.start_io()
