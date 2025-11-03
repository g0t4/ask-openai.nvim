import os
import logging
from pathlib import Path
from lsp.chunks.identified import IdentifiedChunk
from lsp.logs import get_logger

logger_uncovered = get_logger(__name__)
logger_uncovered.setLevel(logging.DEBUG)

def debug_uncovered_nodes(tree, source_bytes, identified_chunks: list[IdentifiedChunk], path: Path):
    if not logger_uncovered.isEnabledForDebug():
        return
    _debug_uncovered_nodes(tree, source_bytes, identified_chunks, path)

def _debug_uncovered_nodes(tree, source_bytes, identified_chunks: list[IdentifiedChunk], path: Path):
    # * collect covered node byte spans
    covered_spans = []
    for chunk in identified_chunks:
        for node in chunk.sibling_nodes:
            covered_spans.append((node.start_byte, node.end_byte))

    # * merge overlapping or contiguous spans
    covered_spans.sort()
    merged_covered_spans = []
    if len(covered_spans) > 0:
        cur_start, cur_end = covered_spans[0]
        for start, end in covered_spans[1:]:
            if start <= cur_end:
                # contiguous (or overlapping) => combine spans
                cur_end = max(cur_end, end)
            else:
                # start > cur_end (not contiguous == uncovered span from cur_end => start)
                combined_span = (cur_start, cur_end)
                merged_covered_spans.append(combined_span)
                cur_start, cur_end = start, end
        last_combined = (cur_start, cur_end)
        merged_covered_spans.append(last_combined)

    # * invert merged_covered_spans to get uncovered byte ranges
    uncovered_spans = []
    last_end = 0
    for start, end in merged_covered_spans:
        if start > last_end:
            # gap (last_end => start) == uncovered span
            uncovered_spans.append((last_end, start))
        last_end = end
    total_bytes = len(source_bytes)
    if last_end < total_bytes:
        uncovered_spans.append((last_end, total_bytes))

    relative_path = path.relative_to(os.getcwd())

    if not uncovered_spans:
        # logger_uncovered.debug(f" **** NO uncoverd nodes: {relative_path} **** ")
        return
    logger_uncovered.debug(f"[bold on red] *********************** Uncovered nodes {relative_path} *********************** [/]")
    if not covered_spans:
        logger_uncovered.debug("[red]No covered nodes to subtract.[/]")

    # * log uncovered code
    for start, end in uncovered_spans:
        text = source_bytes[start:end].decode("utf-8", errors="replace").rstrip()
        if text.strip():
            start_line = source_bytes[:start].count(b"\n") + 1
            end_line = start_line + text.count("\n")
            # TODO compute start/end_column too (so I can use this for sliding window on only uncovered code)
            #  might be feasible to use the nodes and determine contiguous node ranges... then I'd have start/end_point for line/column ranges for covered vs uncovered
            #    without having to recompute line and column numbers
            #    OR just add good tests of recomputing line/column
            logger_uncovered.debug(f"[black on yellow] uncovered bytes (within lines: {start_line}–{end_line}) [/]\n{text}\n")
