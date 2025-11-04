def attach_decorators(node, sibling_nodes: list) -> None:
    prev = node.prev_sibling
    prev_is_decorator = prev and prev.type == "decorator"
    if not prev_is_decorator:
        return
    # TODO any other constraints?
    # FYI I feel like this should be some sort of explorer or visitor that can look back at nodes before a node and decide what to include and under what conditions?
    sibling_nodes.insert(0, prev)
    attach_decorators(prev, sibling_nodes)
