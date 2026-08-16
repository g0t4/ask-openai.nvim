from tree_sitter import Node


def attach_lua_doc_comments(node: Node, chunk_nodes: list) -> None:
    while True:
        prev = node.prev_sibling
        if prev is None:
            return

        if prev.type != "comment":
            break

        comment_end_line = prev.end_point[0]
        node_start_line = node.start_point[0]
        is_blank_line_between = comment_end_line != node_start_line - 1
        if is_blank_line_between:
            break

        chunk_nodes.insert(0, prev)
        node = prev
