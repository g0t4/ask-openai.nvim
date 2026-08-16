def attach_go_type_keyword(node, accumulated: list) -> None:
    """ prepend the 'type' keyword from the parent type_declaration.

    go's type_spec node does NOT include the 'type' keyword -- it lives as
    child 0 of the enclosing type_declaration (e.g. `type Person struct {...}`).
    """
    parent = node.parent
    if not parent or parent.type != "type_declaration":
        return
    type_keyword = parent.child(0)
    if type_keyword and type_keyword.type == "type":
        accumulated.insert(0, type_keyword)
