import argparse
import asyncio
import json
import os
from pathlib import Path
import subprocess
import sys
import termios
import time
import tty
import rich
from datetime import datetime
from typing import List, Optional

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------
def find_trace_files(base_dir: Path) -> List[Path]:
    """
    Walk ``base_dir`` looking for <unix_timestamp>-trace.json files
    Returns a sorted list of Paths ordered chronologically.
    """
    pattern = "**/[0-9]*-trace.json"
    files = sorted(base_dir.glob(pattern), key=lambda p: int(p.stem.split("-")[0]))
    return files

def most_recent_trace(files: List[Path]) -> Optional[Path]:
    """Return the newest trace file or ``None`` if the list is empty."""
    return files[-1] if files else None

def load_trace_metadata(trace_path: Path) -> dict:
    """Read the JSON file and return its content (or an empty dict on error)."""
    try:
        with trace_path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}

def launch_chat_viewer(trace_path: Path) -> None:
    subprocess.run(["fish", "-i", "-c", f"view_trace {trace_path}"], check=False)

class TraceBrowser:

    def __init__(self, base_dir: Path) -> None:
        self.base_dir = base_dir.resolve()
        self.traces = find_trace_files(self.base_dir)
        self.index = len(self.traces) - 1  # start at most recent
        self._print_header()

    def _print_header(self) -> None:
        print("=== Trace Browser REPL ===")
        print("Commands:")
        print("  <Enter>   – open current trace in chat_viewer")
        print("  left/right arrows – move backward/forward in time")
        print("  q         – quit")
        print("--------------------------")

    def _current_trace(self) -> Optional[Path]:
        if 0 <= self.index < len(self.traces):
            return self.traces[self.index]
        return None

    def _show_current(self) -> None:
        trace = self._current_trace()
        if trace:
            dataset_root = self.base_dir.parent
            trace_path_str = str(trace.resolve())
            prefix_path_str = str(Path(dataset_root).resolve())
            display_path = trace_path_str \
                .removeprefix(prefix_path_str) \
                .removeprefix(os.sep)

            meta = load_trace_metadata(trace)
            ts = datetime.fromtimestamp(int(trace.stem.split("-")[0]))
            print(f"[{self.index + 1}/{len(self.traces)}] {display_path}  ({ts.isoformat()})")
            print(f"  summary: {meta.get('summary', 'n/a')}")

        else:
            print("No trace files found.")

    def _move(self, step: int) -> None:
        new_index = self.index + step
        if 0 <= new_index < len(self.traces):
            self.index = new_index
            self._show_current()
        else:
            print("No more traces in that direction.")

    def on_csi(self, sequence):
        UP_ARROW = b'\x1b[A'
        DOWN_ARROW = b'\x1b[B'
        RIGHT_ARROW = b'\x1b[C'
        LEFT_ARROW = b'\x1b[D'

        if sequence == UP_ARROW:
            browser._move(-1)  # treat as back
        elif sequence == DOWN_ARROW:
            pass  # no action defined
        elif sequence == RIGHT_ARROW:
            browser._move(1)
        elif sequence == LEFT_ARROW:
            browser._move(-1)  # treat as forward
        # Add more CSI handling here if needed.

async def main2(browser: TraceBrowser):
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    tty.setcbreak(fd)
    try:
        reader = asyncio.StreamReader()
        protocol = asyncio.StreamReaderProtocol(reader)
        loop = asyncio.get_running_loop()
        await loop.connect_read_pipe(lambda: protocol, sys.stdin)

        while True:
            char = await reader.readexactly(1)

            ESCAPE = b'\x1b'
            if char == ESCAPE:

                async def read_escape_sequence():
                    # https://en.wikipedia.org/wiki/ANSI_escape_code#Control_Sequence_Introducer_commands
                    # - followed by any number (including none) of "parameter bytes" in the range 0x30–0x3F (ASCII 0–9:;<=>?)
                    # - then by any number of "intermediate bytes" in the range 0x20–0x2F (ASCII space and !"#$%&'()*+,-./)
                    # - then finally by a single "final byte" in the range 0x40–0x7E (ASCII @A–Z[\]^_`a–z{|}~)
                    #
                    # Most arrow key sequences are 2 more bytes (e.g. ESC [ A).
                    # Read until we have a non‑numeric byte or we reach a reasonable limit.
                    sequence = ESCAPE
                    # Read the next byte; if it's '[' we expect a final character like 'A', 'B', etc.
                    try:
                        next_byte = await reader.readexactly(1)
                        sequence += next_byte
                        if next_byte == b'[':
                            # Read the final character of the CSI sequence.
                            final = await reader.readexactly(1)
                            sequence += final
                    except Exception as e:
                        rich.print(f"[red]Failed waiting for CSI sequence, skipping sequence: {e}")
                        return

                    browser.on_csi(sequence)

                await read_escape_sequence()
                continue

            if char == b'b':
                browser._move(-1)
            elif char == b'f':
                browser._move(1)
            elif char == b'\n':
                trace = browser._current_trace()
                if trace:
                    launch_chat_viewer(trace)
                else:
                    print("No trace to display.")
            elif char == b'q':
                print("Exiting.")
                break
            else:
                rich.print(f"[dim]no handler for {char=}[/]")

    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

def main() -> None:
    parser = argparse.ArgumentParser(description="Trace browser REPL")
    parser.add_argument(
        "type",
        nargs="?",
        default="fims",
        help="trace type: fims, rewrite, agents",
    )
    args = parser.parse_args()
    base_path = Path(os.getenv("HOME") + "/repos/github/g0t4/datasets/ask_traces/" + args.type)

    if not base_path.is_dir():
        print(f"Error: {base_path} is not a directory.", file=sys.stderr)
        sys.exit(1)

    browser = TraceBrowser(base_path)
    asyncio.run(main2(browser))

if __name__ == "__main__":
    main()
