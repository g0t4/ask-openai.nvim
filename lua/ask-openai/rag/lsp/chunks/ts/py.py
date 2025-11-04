def attach_decorators(node, sibling_nodes: list) -> None:
    prev = node.prev_sibling
    prev_is_decorator = prev and prev.type == "decorator"
    if not prev_is_decorator:
        return

    # TODO any other constraints?
    # FYI I feel like this should be some sort of explorer or visitor that can look back at nodes before a node and decide what to include and under what conditions?
    #  and can I generalize this to more than just python decorators?
    #  c# Attributes: [Serializable], [TestMethod], attached to members or classes, runtime accessible.
    #  c++ Attributes: [[nodiscard]], [[deprecated]], attached to members or classes, runtime accessible
    #      Doxygen comments: /// or /** ... */
    #  rust Attributes: #[derive(Debug)], #[test], etc. - compiler metadata on functions, structs, modules.
    #       Doc comments: /// or //!.

    sibling_nodes.insert(0, prev)
    attach_decorators(prev, sibling_nodes)
