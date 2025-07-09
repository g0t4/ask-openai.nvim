import lsprotocol.types as types
from tree_sitter import Language, Parser


#! TODO do this later ... not now (just wanted idea/reminder)

# Build or load grammar
Language.build_library(
    'build/my-languages.so',
    ['tree-sitter-python'],
)
PY_LANGUAGE = Language('build/my-languages.so', 'python')
parser = Parser()
parser.set_language(PY_LANGUAGE)

def on_open(params: types.DidOpenTextDocumentParams):
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
