def attach_doc_comments(node, sibling_nodes: list) -> None:
    prev = node.prev_sibling
    prev_is_doc_comment = prev and prev.type == "comment"
    if not prev_is_doc_comment:
        return
    # TODO ensure not blank line between (comment's end_point will have line # that is 2 less than node's start_point=>line)

    sibling_nodes.insert(0, prev)
    attach_doc_comments(prev, sibling_nodes)
