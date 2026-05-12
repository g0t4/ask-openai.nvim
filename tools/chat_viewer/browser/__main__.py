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
        # tools/chat_viewer/browser/__main__.py
        trace = self._current_trace()
        if trace:
            dataset_root = self.base_dir.parent
            trace_path_str = str(trace.resolve())
            prefix_path_str = str(Path(dataset_root).resolve())
            if trace_path_str.startswith(prefix_path_str):
                display_path = trace_path_str[len(prefix_path_str):].lstrip(os.sep)
            else:
                display_path = trace_path_str

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
            ch = await reader.readexactly(1)

            # If we receive an ESC character, read the rest of the escape sequence.
            if ch == b'\x1b':
                # Most arrow key sequences are 2 more bytes (e.g. ESC [ A).
                # Read until we have a non‑numeric byte or we reach a reasonable limit.
                seq = b'\x1b'
                # Read the next byte; if it's '[' we expect a final character like 'A', 'B', etc.
                try:
                    next_byte = await reader.readexactly(1)
                    seq += next_byte
                    if next_byte == b'[':
                        # TODO buffer this across reads...
                        # Read the final character of the CSI sequence.
                        final = await reader.readexactly(1)
                        seq += final
                except Exception:
                    # If we fail to read the full sequence just ignore it.
                    continue

                # Arrow keys:
                if seq == b'\x1b[A':  # Up arrow
                    browser._move(-1)  # treat as back
                elif seq == b'\x1b[B':  # Down arrow (optional)
                    pass  # no action defined
                elif seq == b'\x1b[C':  # Right arrow (optional)
                    browser._move(1)
                elif seq == b'\x1b[D':  # Left arrow
                    browser._move(-1)  # treat as forward
                # Add more CSI handling here if needed.
                continue  # Skip the rest of the loop for escape sequences.

            # Normal single‑character commands
            print(repr(ch))
            if ch == b'b':
                browser._move(-1)
            elif ch == b'f':
                browser._move(1)
            elif ch == b'\n':
                trace = browser._current_trace()
                if trace:
                    launch_chat_viewer(trace)
                else:
                    print("No trace to display.")
            elif ch == b'q':
                print("Exiting.")
                break

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
