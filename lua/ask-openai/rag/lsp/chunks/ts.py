def func_name(node):
    if node.type != "function_definition":
        return None
    name = node.child_by_field_name("name")
    return name.text.decode() if name else None

def func_sig(func_node, source_bytes: bytes) -> str:
    """
    Build a one-line signature string for a Python function_definition node.
    Includes function name, parameters, and return type if present.
    """
    # required
    name = func_node.child_by_field_name("name")
    params = func_node.child_by_field_name("parameters")

    name_text = source_bytes[name.start_byte:name.end_byte].decode("utf-8")
    params_text = source_bytes[params.start_byte:params.end_byte].decode("utf-8")

    # optional return annotation
    ret = func_node.child_by_field_name("return_type")
    if ret:
        ret_text = source_bytes[ret.start_byte:ret.end_byte].decode("utf-8")
        sig = f"def {name_text}{params_text} -> {ret_text}"
    else:
        sig = f"def {name_text}{params_text}"

    return sig
