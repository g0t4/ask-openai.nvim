import logging

import lsprotocol.types as types
from tree_sitter import Language, Parser
import tree_sitter_python as tspython

PY_LANGUAGE = Language(tspython.language())
parser = Parser(PY_LANGUAGE)

logger = logging.getLogger(__name__)

def on_open(params: types.DidOpenTextDocumentParams):
    if params.text_document.language_id != 'python':
        return
    text = params.text_document.text.encode()
    tree = parser.parse(text)
    root = tree.root_node

    # Traverse tree to find import statements
    imports = []

    def visit(node):
        if node.type in ('import_statement', 'import_from_statement'):
            imports.append(text[node.start_byte:node.end_byte].decode())
        for child in node.children:
            visit(child)

    visit(root)
    print(f"Imports in {params.text_document.uri}:\n" + '\n'.join(imports))

# TODO move to server.py? do I need this?
# @ls.feature('textDocument/sync')
def sync_kind(*_):
    return types.TextDocumentSyncKind.Full
