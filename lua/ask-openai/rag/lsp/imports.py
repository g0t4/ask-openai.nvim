from pygls.server import LanguageServer
from pygls.lsp.types import DidOpenTextDocumentParams, TextDocumentSyncKind
from tree_sitter import Language, Parser

# Build or load grammar
Language.build_library(
    'build/my-languages.so',
    ['tree-sitter-python']
)
PY_LANGUAGE = Language('build/my-languages.so', 'python')
parser = Parser()
parser.set_language(PY_LANGUAGE)

# Language server setup
ls = LanguageServer('py-import-ls', 'v0.1.0')

@ls.feature('textDocument/didOpen')
def on_open(ls: LanguageServer, params: DidOpenTextDocumentParams):
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

@ls.feature('textDocument/sync')
def sync_kind(*_):
    return TextDocumentSyncKind.Full

if __name__ == '__main__':
    ls.start_io()

