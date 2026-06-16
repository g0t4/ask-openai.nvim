def attach_py_decorators(node, accumulated_decorators: list) -> None:
    while True:
        prev = node.prev_sibling
        prev_is_decorator = prev and prev.type == "decorator"
        if not prev_is_decorator:
            return

        accumulated_decorators.insert(0, prev)
        node = prev
