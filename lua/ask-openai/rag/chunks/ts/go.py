from chunks.identified import IdentifiedChunk


def signature_for_type(node, source_bytes: bytes) -> str:
    # node is a 'type_spec' (go)
    #   - type_identifier + struct_type   => "type Person struct"
    #   - type_identifier + interface_type=> "type Shape interface"
    #   - type_identifier + '='           => "type ID"
    # the 'type' keyword is child 0 of the parent type_declaration
    type_keyword = None
    if node.parent and node.parent.type == "type_declaration":
        type_keyword = node.parent.child(0)
    if type_keyword and type_keyword.type == "type":
        signature = source_bytes[type_keyword.start_byte:type_keyword.end_byte].decode() + " "
    else:
        signature = "type "

    for child in node.children:
        if child.type in ("struct_type", "interface_type"):
            kind = source_bytes[child.start_byte:child.end_byte].decode().split()[0]
            name = source_bytes[node.start_byte:child.start_byte].decode().strip()
            return f"{signature}{name} {kind}"
        if child.type == "=":
            name = source_bytes[node.start_byte:child.start_byte].decode().strip()
            return f"{signature}{name}"

    # no body (e.g. `type X int`)
    return signature + node.text.decode().strip()


def signature_for_type_group(type_children: list, source_bytes: bytes) -> str:
    # type_children: the type_spec / type_alias children of a type_declaration
    # signature is a title of the group's type names, e.g. "type A, B, C"
    names = []
    for child in type_children:
        name_node = child.child(0)
        if name_node and name_node.type == "type_identifier":
            names.append(source_bytes[name_node.start_byte:name_node.end_byte].decode())
    return "type " + ", ".join(names)


def chunks_for_type_declaration(node, source_bytes: bytes) -> list[IdentifiedChunk]:
    """ 0+ chunks from a go type_declaration.

    - single type  => one chunk (the whole declaration, 'type' included)
    - multiple     => a grouped chunk + one chunk per type (do both)
    - empty group  => zero chunks
    """
    type_children = [c for c in node.children if c.type in ("type_spec", "type_alias")]

    if len(type_children) == 1:
        return [IdentifiedChunk(
            sibling_nodes=[node],
            signature=signature_for_type(type_children[0], source_bytes),
        )]

    if len(type_children) > 1:
        chunks = [IdentifiedChunk(
            sibling_nodes=[node],
            signature=signature_for_type_group(type_children, source_bytes),
        )]
        chunks += [
            IdentifiedChunk(
                sibling_nodes=[child],
                prefix="type ",
                signature=signature_for_type(child, source_bytes),
            )
            for child in type_children
        ]
        return chunks

    return []
