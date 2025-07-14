import sys
import os
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
    logger.debug(f"analyzing imports from {params.text_document.uri}")

    text = params.text_document.text.encode()
    tree = parser.parse(text)
    root = tree.root_node

    modules = []
    resolved_modules = []

    def module_to_paths(module: str, search_paths: list[str]) -> list[str]:
        parts = module.split(".")
        rel_path = os.path.join(*parts)
        candidates = [rel_path + ".py", os.path.join(rel_path, "__init__.py")]

        for base in search_paths:
            for c in candidates:
                full = os.path.join(base, c)
                if os.path.isfile(full):
                    return [full]
        return []

    def get_search_paths(file_path: str) -> list[str]:
        return [os.path.dirname(file_path)] + sys.path

    def visit(node, level: int):
        level_indent = "  " * level
        # logger.debug(f"{level_indent}visiting {node.type}: {text[node.start_byte:node.end_byte].decode()}")

        if node.type == "import_statement":
            # import a.b.c
            for child in node.children:
                if child.type == "aliased_import":
                    for child2 in child.children:
                        if child2.type == "dotted_name":
                            my_text = text[child2.start_byte:child2.end_byte].decode()
                            logger.debug(f"{level_indent}** aliased import => dotted_name: {my_text}")
                            modules.append(my_text)
                            break  # stop on first
                if child.type == "dotted_name":
                    my_text = text[child.start_byte:child.end_byte].decode()
                    logger.debug(f"{level_indent}** dotted name: {text[child.start_byte:child.end_byte].decode()}")
                    modules.append(my_text)
                    break  # stop on first (else from foo import bar... gets to both foo and bar.. they're both dotted_names)
        elif node.type == "import_from_statement":
            # from a.b import x
            for child in node.children:
                if child.type == "dotted_name":
                    my_text = text[child.start_byte:child.end_byte].decode()
                    logger.debug(f"{level_indent}** dotted name: {text[child.start_byte:child.end_byte].decode()}")
                    modules.append(my_text)
                    break  # stop on first
                # elif child.type == "relative_import":
                #     # e.g. from .. import x
                #     dots = text[child.start_byte:child.end_byte].decode()
                #     modules.append(dots)  # relative marker
        else:
            # when you find topmost level of import, don't visit it further
            # else, from foo import bar => picks up foo, then picks up bar as if it were "import bar" alone when it is not!
            for child in node.children:
                visit(child, level + 1)

    visit(root, level=0)
    for m in modules:
        resolved = module_to_paths(m, get_search_paths(params.text_document.uri))
        resolved_modules.extend(resolved)
    logger.debug(f"Imports in {params.text_document.uri}:\n" + '\n'.join(modules))
    logger.debug(f"Resolved imports in {params.text_document.uri}:\n" + '\n'.join(resolved_modules))

    # TODO! include as context!

# TODO move to server.py? do I need this?
# @ls.feature('textDocument/sync')
def sync_kind(*_):
    return types.TextDocumentSyncKind.Full
