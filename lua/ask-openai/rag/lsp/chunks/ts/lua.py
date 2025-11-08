def attach_doc_comments(node, sibling_nodes: list) -> None:
    prev = node.prev_sibling
    prev_is_doc_comment = prev and prev.type == "comment"
    if not prev_is_doc_comment:
        return
    # TODO ensure not blank line between (comment's end_point will have line # that is 2 less than node's start_point=>line)

        # Ensure there is no blank line between the comment and the node
    # The comment's end line should be exactly one line before the node's start line
    comment_end_line = prev.end_point[0]
    node_start_line = node.start_point[0]
    if comment_end_line != node_start_line - 1:
        return
    # # Check for any other non-comment nodes between the comment and the current node
    # # If there are any such nodes, the comment should not be attached
    # sibling = prev.prev_sibling
    # while sibling:
    #     # If we encounter a non-whitespace, non-comment node before reaching a blank line, abort
    #     if sibling.type not in ("comment", "blank"):
    #         return
    #     # Stop if we encounter a blank line (i.e., a node that represents a line break)
    #     if sibling.type == "blank":
    #         return
    #     sibling = sibling.prev_sibling
    # # If we made it here

    sibling_nodes.insert(0, prev)
    attach_doc_comments(prev, sibling_nodes)
