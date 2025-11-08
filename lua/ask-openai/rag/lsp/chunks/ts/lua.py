def attach_doc_comments(node, accumulated_comments: list) -> None:
    while True:
        prev = node.prev_sibling
        prev_is_doc_comment = prev and prev.type == "comment"
        if not prev_is_doc_comment:
            break

        comment_end_line = prev.end_point[0]
        node_start_line = node.start_point[0]
        is_blank_line_between = comment_end_line != node_start_line - 1
        if is_blank_line_between:
            break

        accumulated_comments.insert(0, prev)
        node = prev
