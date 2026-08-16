from dataclasses import dataclass
from tree_sitter import Node

@dataclass(slots=True)
class IdentifiedChunk:
    # i.e. when primary has doc_comments/annotations/decorators before it, these are then siblings and there is not single node
    nodes: list[Node]
    signature: str = ""

    def number_lines(self):
        # ? throw if nodes are not adjacent?
        return sum(
            node.end_point[0] - node.start_point[0] + 1 \
                   for node in self.nodes
        )

# # PRN switch to NamedTuple?
# #  pros: hashable, better for caching
# #  cons: immutable
# from typing import NamedTuple
# class IdentifiedChunk(NamedTuple):
#     nodes: tuple[Node, ...]
#     signature: str
