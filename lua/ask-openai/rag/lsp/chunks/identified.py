from dataclasses import dataclass
from tree_sitter import Node

@dataclass(slots=True)
class IdentifiedChunk:
    # i.e. when primary has doc_comments/annotations/decorators before it, these are then siblings and there is not single node
    sibling_nodes: list[Node]
    signature: str = ""

# # PRN switch to NamedTuple?
# #  pros: hashable, better for caching
# #  cons: immutable
# from typing import NamedTuple
# class IdentifiedChunk(NamedTuple):
#     sibling_nodes: tuple[Node, ...]
#     signature: str
