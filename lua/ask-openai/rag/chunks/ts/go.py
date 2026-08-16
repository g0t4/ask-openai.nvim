from chunks.identified import IdentifiedChunk


def signature_for_type(node, source_bytes: bytes) -> str:
    # node is a 'type_spec' (go)
    #   - type_identifier + struct_type   => "type Person struct"
    #   - type_identifier + interface_type=> "type Shape interface"
    #   - type_identifier + '='           => "type ID"
    # every go type_declaration starts with the 'type' keyword, so the prefix is constant
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


def chunks_for_type_declaration(type_declaration, source_bytes: bytes) -> list[IdentifiedChunk]:
    """ 0+ chunks from a go type_declaration.

    - single type  => one chunk (the whole declaration, 'type' included)
    - multiple     => a grouped chunk + one chunk per type (do both)
    - empty group  => zero chunks
    """
    types = [c for c in type_declaration.children if c.type in ("type_spec", "type_alias")]

    if len(types) == 1:
        return [IdentifiedChunk(
            sibling_nodes=[type_declaration],
            signature=signature_for_type(types[0], source_bytes),
        )]

    if len(types) > 1:
        chunks = [IdentifiedChunk(
            sibling_nodes=[type_declaration],
            signature=signature_for_type_group(types, source_bytes),
        )]
        chunks += [
            IdentifiedChunk(
                sibling_nodes=[type],
                signature=signature_for_type(type, source_bytes),
            )
            for type in types
        ]
        return chunks

    return []
