def attach_decorators(node, sibling_nodes: list) -> None:
    prev = node.prev_sibling
    prev_is_decorator = prev and prev.type == "decorator"
    if not prev_is_decorator:
        return

    # TODO any other constraints?

    sibling_nodes.insert(0, prev)
    attach_decorators(prev, sibling_nodes)
