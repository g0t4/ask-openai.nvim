# := vim.lsp.get_log_path()
# tail -F ~/.local/state/nvim/lsp.log

#
# v1 migration:
#   https://pygls.readthedocs.io/en/latest/pygls/howto/migrate-to-v1.html
# FYI guides have v2 examples already... ugh
from pygls.server import LanguageServer
from lsprotocol.types import (
    CompletionItem,
    CompletionList,
    CompletionParams,
    ExecuteCommandParams,
)
import lsprotocol.types as types

# print(f'{__package__=}')
import lsp.rag as rag
from .logs import logging

server = LanguageServer("ask_language_server", "v0.1")

@server.feature(types.INITIALIZED)
def on_initialized(server):
    #  FYI server is managed by the client!
    #  client sends initialize request first => waits for server to send InitializeResult
    #    https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialize
    #  then, client sends initialized (this) request => waits for completion
    #    does not send other requests until initialized is done
    #  https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialized
    rag.load_model()

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
