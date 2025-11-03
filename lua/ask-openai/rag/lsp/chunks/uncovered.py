import os
import logging
from dataclasses import dataclass
from pathlib import Path

import portion as P
from tree_sitter import Tree
from lsp.chunks.identified import IdentifiedChunk
from lsp.logs import get_logger

logger_uncovered = get_logger(__name__)
logger_uncovered.setLevel(logging.DEBUG)

@dataclass
class UncoveredCode:
    text: str
    start_line_base1: int
    end_line_base1: int

    def start_line_base0(self) -> int:
        return self.start_line_base1 - 1

    def end_line_base0(self) -> int:
        return self.end_line_base1 - 1

def debug_uncovered_nodes(tree: Tree, source_bytes: bytes, chunks: list[IdentifiedChunk], relative_path: Path) -> list[UncoveredCode]:
    if not logger_uncovered.isEnabledForDebug():
        return []
    uncovered_code = _debug_uncovered_nodes(tree, source_bytes, chunks)

    if not uncovered_code:
        # logger_uncovered.debug(f" **** NO uncovered nodes: {relative_path} **** ")
        return []

    # * log uncovered code
    logger_uncovered.debug(f"[bold on red] *********************** Uncovered nodes {relative_path} *********************** [/]")
    for c in uncovered_code:
        logger_uncovered.debug(
            f"[black on yellow] uncovered bytes (within lines: {c.start_line_base1}–{c.end_line_base1}) [/]\n{c.text}\n" \
        )
    return uncovered_code

def _debug_uncovered_nodes(tree: Tree, source_bytes: bytes, chunks: list[IdentifiedChunk]) -> list[UncoveredCode]:
    print()

    # * collect covered node byte spans
    covered_spans = P.empty()
    for chunk in chunks:
        for node in chunk.sibling_nodes:
            covered = P.openclosed(node.start_byte, node.end_byte)
            print("covered", covered)
            covered_spans |= covered
    print("covered_spans (combined)", covered_spans)

    uncovered_spans = P.openclosed(0, len(source_bytes)) - covered_spans

    # * collect uncovered code
    uncovered_code: list[UncoveredCode] = []
    for span in uncovered_spans:
        print("uncovered", span)
        assert span.left == P.Bound.OPEN
        assert span.right == P.Bound.CLOSED
        # FYI logic below assumes open/closed (use assertions for now to ensure that reality)
        #  slice below treats end as not-inclusive, thus matches open/closed
        start = span.lower
        end = span.upper
        text = source_bytes[start:end].decode("utf-8", errors="replace").rstrip()
        if text.strip():
            start_line_base1 = source_bytes[:start].count(b"\n") + 1
            end_line_base1 = start_line_base1 + text.count("\n")
            # FYI I am not computing column offsets, for uncovered code purposes I think that's fine for now b/c...
            # - this is only going to be for sliding window "fallback" chunker which is 100% fine to cover a smidge extra
            # - I might even cover X lines around window too so columns on the start/end line don't matter
            uncovered_code.append(UncoveredCode(text=text, start_line_base1=start_line_base1, end_line_base1=end_line_base1))
        # else:
        #     # ? return whitespace only sections?
        #     start_line = source_bytes[:start].count(b"\n") + 1
        #     end_line = start_line
        #     uncovered_code.append(UncoveredCode(text=text, start_line_base0=start_line, end_line_base0=end_line))

    return uncovered_code
