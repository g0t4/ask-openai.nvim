def attach_decorators(node, accumulated_decorators: list) -> None:
    prev = node.prev_sibling
    prev_is_decorator = prev and prev.type == "decorator"
    if not prev_is_decorator:
        return

    # TODO any other constraints?

    accumulated_decorators.insert(0, prev)
    attach_decorators(prev, accumulated_decorators)
