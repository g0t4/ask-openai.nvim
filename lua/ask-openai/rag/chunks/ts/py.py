from tree_sitter import Node


def attach_py_decorators(node: Node, chunk_nodes: list) -> None:
    while True:
        prev = node.prev_sibling
        if prev is None:
            return

        if prev.type != "decorator":
            return

        chunk_nodes.insert(0, prev)
        node = prev
