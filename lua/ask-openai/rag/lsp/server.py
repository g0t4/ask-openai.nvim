# := vim.lsp.get_log_path()
# tail -F ~/.local/state/nvim/lsp.log

#
# v1 migration:
#   https://pygls.readthedocs.io/en/latest/pygls/howto/migrate-to-v1.html
# FYI guides have v2 examples already... ugh
import logging
import os
from pygls.server import LanguageServer
from lsprotocol.types import (
    TEXT_DOCUMENT_COMPLETION,
    CompletionItem,
    CompletionList,
    CompletionParams,
    ExecuteCommandParams,
)

log_file = os.path.expanduser("~/.local/share/ask-openai/language.server.log")
logging.basicConfig(filename=log_file, level=logging.DEBUG)

server = LanguageServer("ask_language_server", "v0.1")

@server.feature(TEXT_DOCUMENT_COMPLETION)
def completions(params: CompletionParams):
    # FYI this is just for initial testing, ok to nuke as I have no plans for completions support
    items = []
    document = server.workspace.get_document(params.text_document.uri)
    current_line = document.lines[params.position.line].strip()
    if current_line.endswith("hello."):
        items = [
            CompletionItem(label="world"),
            CompletionItem(label="friend"),
        ]
    return CompletionList(is_incomplete=False, items=items)

@server.command("ask.ragQuery")
def rag_query(ls: LanguageServer, params: ExecuteCommandParams):
    logging.info("Query: %s", params)
    # your logic
    return {"result": "some value"}

server.start_io()
