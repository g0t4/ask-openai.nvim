import os
import logging
from dataclasses import dataclass
from pathlib import Path
from typing import NamedTuple

import portion as P
from tree_sitter import Tree
from lsp.chunks.identified import IdentifiedChunk
from lsp.logs import get_logger
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
BOLD = "\x1b[1m"
ITALIC = "\x1b[3m"
UNDERLINE = "\x1b[4m"

class TroubleshootCodeInterval(NamedTuple):
    interval: P.Interval
    text: str
    type: str

@dataclass(slots=True)
class UncoveredCode:
    text: str
    start_line_base1: int
    end_line_base1: int
    byte_interval_base0: P.Interval

    def start_line_base0(self) -> int:
        return self.start_line_base1 - 1

    def end_line_base0(self) -> int:
        return self.end_line_base1 - 1

    def is_whitespace_or_empty(self) -> bool:
        # FYI should not be empty but doesn't hurt to include it if that changes later
        return self.text == '' or self.text.isspace()

    def troubleshooter(self):
        return TroubleshootCodeInterval(interval=self.byte_interval_base0, text=self.text, type="uncovered")

def create_uncovered_code(source_bytes: bytes, byte_interval) -> UncoveredCode:
    assert byte_interval.left == P.Bound.OPEN
    assert byte_interval.right == P.Bound.CLOSED

    # FYI logic below assumes open/closed (use assertions for now to ensure that reality)
    #  slice below treats end as not-inclusive, thus matches open/closed
    start_byte_base0: int = byte_interval.lower
    end_byte_base0: int = byte_interval.upper

    text = source_bytes[start_byte_base0:end_byte_base0].decode("utf-8", errors="replace")

    # FYI I am not computing column offsets, for uncovered code purposes I think that's fine for now b/c...
    # - this is only going to be for sliding window "fallback" chunker which is 100% fine to cover a smidge extra
    # - I might even cover X lines around window too so columns on the start/end line don't matter
    start_line_base1 = source_bytes[:start_byte_base0].count(b"\n") + 1
    end_line_base1 = start_line_base1 + text.count("\n")

    return UncoveredCode(
        text=text,
        byte_interval_base0=byte_interval,
        start_line_base1=start_line_base1,
        end_line_base1=end_line_base1,
    )

def debug_uncovered_nodes(tree: Tree, source_bytes: bytes, chunks: list[IdentifiedChunk], relative_path: Path) -> list[UncoveredCode]:
    if not logger_uncovered.isEnabledForDebug():
        return []
    uncovered_code = _build_uncovered_intervals(tree, source_bytes, chunks, show_intervals=True)

    if not uncovered_code:
        return []

    # * log uncovered code
    buffer = StringIO()
    buffer.write(f"\n{BOLD}{REDBG}** Uncovered nodes {relative_path}{RESET}\n")
    for code in uncovered_code:
        if code.start_line_base1 == code.end_line_base1:
            line_desc = f"line {code.start_line_base1}"
        else:
            line_desc = f"lines {code.start_line_base1}–{code.end_line_base1}"

        if code.is_whitespace_or_empty():
            buffer.write(f"{BLACK}{CYANBG}uncovered whitespace within {line_desc}{RESET}\n")
            buffer.write(repr(code.text))
            buffer.write("\n")
            continue

        buffer.write(f"{BLACK}{YELLOWBG}uncovered bytes within {line_desc}{RESET}\n")
        buffer.write(code.text)
        if code.text[-1] != "\n":
            buffer.write("\n")

        # use console directly so I can disable markup for code
    logger_uncovered.debug_no_markup(buffer.getvalue())

    return uncovered_code

def create_merged_troubleshooter(source_bytes: bytes, interval: P.Interval):
    return TroubleshootCodeInterval(
        interval=interval,
        text=source_bytes[interval.lower:interval.upper].decode("utf-8", errors="replace"),
        type="merged_covered",
    )

def _build_uncovered_intervals(tree: Tree, source_bytes: bytes, chunks: list[IdentifiedChunk], show_intervals=False) -> list[UncoveredCode]:

    merged_covered_intervals = P.empty()

    t_covered: list[TroubleshootCodeInterval] = []
    for chunk in chunks:
        for node in chunk.sibling_nodes:
            # back to treating as standalone nodes, is perfectly fine and best way to keep byte/(line,col) alignments
            covered = P.openclosed(node.start_byte, node.end_byte)
            if show_intervals:
                text = source_bytes[node.start_byte:node.end_byte].decode("utf-8", errors="replace")
                t_covered.append(TroubleshootCodeInterval(interval=covered, text=text, type="covered"))
            merged_covered_intervals |= covered

    uncovered_intervals = P.openclosed(0, len(source_bytes)) - merged_covered_intervals

    # * collect uncovered code
    uncovered_code: list[UncoveredCode] = []
    for interval in uncovered_intervals:
        code = create_uncovered_code(source_bytes, interval)
        uncovered_code.append(code)

    if show_intervals:
        # ***! This view of code covered/not is ESSENTIAL to understand what is happening
        #  i.e. immediately obvious why we get leading and trailing \n in specific situations
        #  run the myriad of test cases in uncovered_tests and then look at the output w.r.t. this debug section

        t_merged = [create_merged_troubleshooter(source_bytes, interval) for interval in merged_covered_intervals]
        t_uncovered = [code.troubleshooter() for code in uncovered_code]

        # troubleshoots = t_uncovered + t_covered # show covered intervals (NOT merged)
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
