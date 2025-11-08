def attach_doc_comments(node, accumulated_comments: list) -> None:
    prev = node.prev_sibling
    prev_is_doc_comment = prev and prev.type == "comment"
    if not prev_is_doc_comment:
        return

    # * Ensure no blank line between the comment and the node
    comment_end_line = prev.end_point[0]
    node_start_line = node.start_point[0]
    if comment_end_line != node_start_line - 1:
        return

    accumulated_comments.insert(0, prev)

    # TODO remove tail recursion using smth like what gptoss120b suggested:
    # sibling = prev.prev_sibling
    # while sibling:
    #     if sibling.type not in ("comment"):
    #         return
    #     sibling = sibling.prev_sibling
    attach_doc_comments(prev, accumulated_comments)
