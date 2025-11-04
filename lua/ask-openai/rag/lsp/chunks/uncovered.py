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

# * ANSI colors
# foreground:
BLACK = "\x1b[30m"
RED = "\x1b[31m"
GREEN = "\x1b[32m"
YELLOW = "\x1b[33m"
BLUE = "\x1b[34m"
MAGENTA = "\x1b[35m"
CYAN = "\x1b[36m"
WHITE = "\x1b[37m"
# background:
BLACKBG = "\x1b[40m"
REDBG = "\x1b[41m"
GREENBG = "\x1b[42m"
YELLOWBG = "\x1b[43m"
BLUEBG = "\x1b[44m"
MAGENTABG = "\x1b[45m"
CYANBG = "\x1b[46m"
WHITEBG = "\x1b[47m"
#
RESET = "\x1b[0m"

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
    uncovered_code = _debug_uncovered_nodes(tree, source_bytes, chunks, show_intervals=True)

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

def _debug_uncovered_nodes(tree: Tree, source_bytes: bytes, chunks: list[IdentifiedChunk], show_intervals=False) -> list[UncoveredCode]:

    # * collect covered node byte spans
    merged_covered_spans = P.empty()

    class TroubleshootNode(NamedTuple):
        interval: P.Interval
        text: str
        type: str

    t_covered: list[TroubleshootNode] = []
    for chunk in chunks:
        for node in chunk.sibling_nodes:
            # back to treating as standalone nodes, is perfectly fine and best way to keep byte/(line,col) alignments
            covered = P.openclosed(node.start_byte, node.end_byte)
            text = source_bytes[node.start_byte:node.end_byte].decode("utf-8", errors="replace")
            if show_intervals:
                t_covered.append(TroubleshootNode(interval=covered, text=text, type="covered"))
            merged_covered_spans |= covered

    uncovered_spans = P.openclosed(0, len(source_bytes)) - merged_covered_spans

    # * collect uncovered code
    uncovered_code: list[UncoveredCode] = []
    t_uncovered: list[TroubleshootNode] = []
    for span in uncovered_spans:
        assert span.left == P.Bound.OPEN
        assert span.right == P.Bound.CLOSED
        # FYI logic below assumes open/closed (use assertions for now to ensure that reality)
        #  slice below treats end as not-inclusive, thus matches open/closed
        start_base0: int = span.lower
        end_base0: int = span.upper

        text = source_bytes[start_base0:end_base0].decode("utf-8", errors="replace")

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

        if show_intervals:
            t_uncovered.append(TroubleshootNode(interval=span, text=text, type="uncovered"))

    if show_intervals:
        # ***! This view of code covered/not is ESSENTIAL to understand what is happening
        #  i.e. immediately obvious why we get leading and trailing \n in specific situations
        #  run the myriad of test cases in uncovered_tests and then look at the output w.r.t. this debug section

        t_merged = [TroubleshootNode(
            interval=m,
            text=source_bytes[m.lower:m.upper].decode("utf-8", errors="replace"),
            type="merged_covered",
        ) for m in merged_covered_spans]

        # troubleshoots = t_uncovered + t_covered # show unmerged covered spans
        troubleshoots = t_uncovered + t_merged

        buffer = StringIO()
        buffer.write("\n")

        for t in sorted(troubleshoots):
            if t.type == "merged_covered":
                style = CYAN
            elif t.type == "covered":
                style = GREEN
            elif t.type == "uncovered":
                style = RED
            else:
                raise Exception("bad type")
            buffer.write(f'{style}{t.interval} - {repr(t.text)}{RESET}\n')

        logger_uncovered.debug_no_markup(buffer.getvalue())

    return uncovered_code
