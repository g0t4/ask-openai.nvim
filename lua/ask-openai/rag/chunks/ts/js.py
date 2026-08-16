from chunks.identified import IdentifiedChunk

# node types representing a function used as an expression (NOT a declaration)
#   e.g. `const add = function(a, b) { ... }`, `const add = (a, b) => { ... }`
FUNCTION_EXPRESSION_NODES = {
    "function_expression",
    "arrow_function",
    "generator_function",
}

# declaration statements that bind a (possibly named) function expression to a variable
VARIABLE_DECLARATION_NODES = {
    "lexical_declaration",  # const / let
    "variable_declaration",  # var
}

# the function body node types used to cut the signature short (skip the body)
BODY_NODE_TYPES = {"statement_block"}


def signature_for_assigned_function(declaration, fn_node, source_bytes: bytes) -> str:
    """ signature for a declaration like `const add = function(a, b) { ... };`

    - block body  => copy declaration up to (exclusive of) the body
                      e.g. `const add = function(a, b)`
                      e.g. `const add = (a, b) =>`
    - concise body (no statement_block, i.e. `x => x * x`)
      => the whole declaration is the signature
    """
    for child in fn_node.children:
        if child.type in BODY_NODE_TYPES:
            return source_bytes[declaration.start_byte:child.start_byte].decode().strip()
    # concise body: whole declaration is the signature (drop trailing `;`)
    return source_bytes[declaration.start_byte:declaration.end_byte].decode().rstrip(";").rstrip()


def chunks_for_function_expression(fn_node, source_bytes: bytes) -> list[IdentifiedChunk]:
    """ 0 or 1 chunks from a JS function expression node.

    A function expression is only semantically relevant when it is bound to a
    variable (i.e. `const foo = function(...) { ... }`). Inline callbacks passed
    as arguments (e.g. `nums.map((x) => x * 2)`) are not standalone chunks, so
    they yield zero chunks here and are left to the enclosing scope / line ranges.

    When relevant, the chunk is the whole declaration statement so the variable
    name (the meaningful identifier) is preserved in both text and signature.
    """
    parent = fn_node.parent
    if parent is None or parent.type != "variable_declarator":
        return []

    declaration = parent.parent
    if declaration is None or declaration.type not in VARIABLE_DECLARATION_NODES:
        return []

    return [IdentifiedChunk(
        nodes=[declaration],
        signature=signature_for_assigned_function(declaration, fn_node, source_bytes),
    )]
