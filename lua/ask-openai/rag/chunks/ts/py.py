def attach_py_decorators(node, sibling_nodes: list) -> None:
    while True:
        prev = node.prev_sibling
        prev_is_decorator = prev and prev.type == "decorator"
        if not prev_is_decorator:
            return

        sibling_nodes.insert(0, prev)
        node = prev
