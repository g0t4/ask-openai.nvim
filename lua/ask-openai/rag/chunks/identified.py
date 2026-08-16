from dataclasses import dataclass
from tree_sitter import Node

@dataclass(slots=True)
class IdentifiedChunk:
    # i.e. when primary has doc_comments/annotations/decorators before it, these are then siblings and there is not single node
    nodes: list[Node]
    signature: str = ""

    def number_lines(self):
        return sum(
            node.end_point[0] - node.start_point[0] + 1 \
                   for node in self.nodes
        )

    def throw_if_non_adjacent(self):
        # TODO use in building chunks (not uncovered code) b/c right now that assumes it is adjacent
        import itertools
        pairs = itertools.pairwise(self.nodes)
        assert all(a.next_sibling == b for a, b in pairs), \
            f"IdentifiedChunk nodes are not adjacent: {pairs}"


# # PRN switch to NamedTuple?
# #  pros: hashable, better for caching
# #  cons: immutable
# from typing import NamedTuple
# class IdentifiedChunk(NamedTuple):
#     nodes: tuple[Node, ...]
#     signature: str
