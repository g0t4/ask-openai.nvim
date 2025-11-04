from dataclasses import dataclass
from tree_sitter import Node

@dataclass(slots=True)
class IdentifiedChunk:
    # i.e. when primary has doc_comments/annotations/decorators before it, these are then siblings and there is not single node
    sibling_nodes: list[Node]
    signature: str = ""
