import os
import logging
from dataclasses import dataclass
from pathlib import Path
from typing import NamedTuple

import portion as P
from tree_sitter import Tree
from lsp.chunks.identified import IdentifiedChunk
from lsp.logs import get_logger
from rich.console import Console
from io import StringIO

logger_uncovered = get_logger(__name__)
logger_uncovered.setLevel(logging.DEBUG)

@dataclass(slots=True)
class UncoveredCode:
    text: str
    start_line_base1: int
    end_line_base1: int
    start_byte_base0: int
    end_byte_base0: int

    def start_line_base0(self) -> int:
        return self.start_line_base1 - 1

    def end_line_base0(self) -> int:
        return self.end_line_base1 - 1

    def is_whitespace_or_empty(self) -> bool:
        # FYI should not be empty but doesn't hurt to include it if that changes later
        return self.text == '' or self.text.isspace()

def debug_uncovered_nodes(tree: Tree, source_bytes: bytes, chunks: list[IdentifiedChunk], relative_path: Path) -> list[UncoveredCode]:
    if not logger_uncovered.isEnabledForDebug():
        return []
    uncovered_code = _debug_uncovered_nodes(tree, source_bytes, chunks)

    if not uncovered_code:
        # logger_uncovered.debug(f" **** NO uncovered nodes: {relative_path} **** ")
        return []

    # * log uncovered code
    buffer = StringIO()  # buffer for single log per file
    # TODO fix wrapping issues between console.print and then logger's rich_handler, for now I am setting width to 200 for console printer:
    #   absolute file path is notorious for causing wrap
    console = Console(file=buffer, force_terminal=True, color_system="truecolor", width=200)
    console.print(
        f"\n** Uncovered nodes {relative_path}",
        style="bold white on red",
        highlight=False,  # avoid highlight on path
    )
    for code in uncovered_code:
        if code.start_line_base1 == code.end_line_base1:
            line_desc = f"line {code.start_line_base1}"
        else:
            line_desc = f"lines {code.start_line_base1}–{code.end_line_base1}"

        if code.is_whitespace_or_empty():
            console.print(f"[black on cyan]uncovered whitespace within {line_desc}[/]", highlight=False)
            console.print(f"{repr(code.text)}", highlight=False)
            continue

        console.print(f"[black on yellow]uncovered bytes within {line_desc}[/]", highlight=False)
        console.print(f"{code.text}", markup=False, highlight=False, end="")  # end="" else each line has a \n after!

        # use console directly so I can disable markup for code
    logger_uncovered.debug_no_markup(buffer.getvalue())

    return uncovered_code

def _debug_uncovered_nodes(tree: Tree, source_bytes: bytes, chunks: list[IdentifiedChunk]) -> list[UncoveredCode]:
    from rich import print
    print()

    # * collect covered node byte spans
    covered_spans = P.empty()

    class TroubleshootNode(NamedTuple):
        interval: P.Interval
        text: str
        covered: bool

    troubleshoots: list[TroubleshootNode] = []

    for chunk in chunks:
        for node in chunk.sibling_nodes:
            covered = P.openclosed(node.start_byte, node.end_byte)
            text = source_bytes[node.start_byte:node.end_byte].decode("utf-8", errors="replace")
            troubleshoots.append(TroubleshootNode(interval=covered, text=text, covered=True))
            covered_spans |= covered
    print("[cyan]COMBINED[/]", covered_spans)

    uncovered_spans = P.openclosed(0, len(source_bytes)) - covered_spans

    # * collect uncovered code
    uncovered_code: list[UncoveredCode] = []
    for span in uncovered_spans:
        assert span.left == P.Bound.OPEN
        assert span.right == P.Bound.CLOSED
        # FYI logic below assumes open/closed (use assertions for now to ensure that reality)
        #  slice below treats end as not-inclusive, thus matches open/closed
        start_base0: int = span.lower
        end_base0: int = span.upper

        # TODO! drop rstrip? why would I need that if the range is not inclusive?
        # TODO seems to be bug that results in \n on front of next line?
        # TODO! why am I getting \n in front and end of middle line?! see multi node tests
        #  ok it is b/c I am subtracing from overall range and there is no node for the skipped whitespace chars... ok
        text = source_bytes[start_base0:end_base0].decode("utf-8", errors="replace")

        troubleshoots.append(TroubleshootNode(interval=span, text=text, covered=False))

        # FYI I am not computing column offsets, for uncovered code purposes I think that's fine for now b/c...
        # - this is only going to be for sliding window "fallback" chunker which is 100% fine to cover a smidge extra
        # - I might even cover X lines around window too so columns on the start/end line don't matter
        start_line_base1 = source_bytes[:start_base0].count(b"\n") + 1
        end_line_base1 = start_line_base1 + text.count("\n")
        code = UncoveredCode(
            text=text,
            start_line_base1=start_line_base1,
            end_line_base1=end_line_base1,
            start_byte_base0=start_base0,
            end_byte_base0=end_base0,
        )
        uncovered_code.append(code)

    for t in sorted(troubleshoots):
        if t.covered:
            style = "green"
        else:
            style = "red"
        print(f'  [{style}]{t.interval} - {repr(t.text)}[/]')

    return uncovered_code
