from tree_sitter import Node


def attach_py_decorators(node: Node, chunk_nodes: list) -> None:
    while True:
        prev = node.prev_sibling
        prev_is_decorator = prev and prev.type == "decorator"
        if not prev_is_decorator:
            return

        chunk_nodes.insert(0, prev)
        node = prev
