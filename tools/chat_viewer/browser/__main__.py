import argparse
import asyncio
import json
import os
import rich
import subprocess
import sys
import termios
import time
import tty
from datetime import datetime, timezone
from pathlib import Path
from rich.table import Table
from typing import List, Optional

from tools.chat_viewer.tree_wrapper import TreeWrapper

def relative_age(past: datetime) -> str:
    """Return a human‑readable relative age like “2 days ago”. """
    now = datetime.now(timezone.utc)
    delta = now - past.astimezone(timezone.utc)

    seconds = int(delta.total_seconds())
    minutes = seconds // 60
    hours = minutes // 60
    days = hours // 24

    if days > 0:
        return f"{days} day{'s' if days != 1 else ''} ago"
    if hours > 0:
        return f"{hours} hour{'s' if hours != 1 else ''} ago"
    if minutes > 0:
        return f"{minutes} minute{'s' if minutes != 1 else ''} ago"
    return f"{seconds} second{'s' if seconds != 1 else ''} ago"

def find_trace_files(base_dir: Path) -> List[Path]:
    """
    Walk ``base_dir`` looking for <unix_timestamp>-trace.json files
    Returns a sorted list of Paths ordered chronologically.
    """
    pattern = "**/[0-9]*-trace.json"
    files = sorted(base_dir.glob(pattern), key=lambda p: int(p.stem.split("-")[0]))
    return files

def load_trace_json(trace_path: Path) -> dict:
    try:
        with trace_path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}

def launch_chat_viewer(trace_path: Path) -> None:
    subprocess.run(["fish", "-i", "-c", f"view_trace {trace_path}"], check=False)

class TraceBrowser:

    def __init__(self, type: str) -> None:
        base_dir = Path(os.getenv("HOME") + "/repos/github/g0t4/datasets/ask_traces/" + type)
        if not base_dir.is_dir():
            print(f"Error: {base_dir} is not a directory.", file=sys.stderr)
            sys.exit(1)
        self.base_dir = base_dir.resolve()

        self.type = type
        self.traces = find_trace_files(self.base_dir)
        self.index = len(self.traces) - 1  # start at most recent
        self.show_current()

    def print_help(self) -> None:
        table = Table(expand=False, title="Help")
        table.add_column(header="Key", justify="right", style="cyan", no_wrap=True)
        table.add_column(header="Description", style="white")

        table.add_row("q", "quit")
        table.add_row("c", "copy current trace path")
        table.add_row("t", "WIP - copy take command to add to datasets repo")
        table.add_row("Enter", "open current trace in chat_viewer")
        table.add_row("←/→", "older / newer")
        table.add_row("h", "help")

        rich.print(table)

    def current_trace(self) -> Optional[Path]:
        if 0 <= self.index < len(self.traces):
            return self.traces[self.index]
        return None

    def show_current(self) -> None:
        trace = self.current_trace()
        if not trace:
            print("No trace files found.")
            return

        dataset_root = self.base_dir.parent
        trace_path_str = str(trace.resolve())
        prefix_path_str = str(Path(dataset_root).resolve())
        display_path = trace_path_str \
            .removeprefix(prefix_path_str) \
            .removeprefix(os.sep)

        ts = datetime.fromtimestamp(int(trace.stem.split("-")[0]))
        relative = relative_age(ts)
        print(f"[{self.index + 1}/{len(self.traces)}] {display_path}  "
              f"({ts.isoformat()}, {relative})")
        # meta = load_trace_json(trace)
        # print(f"  summary: {meta.get('summary', 'n/a')}")

    def newer(self):
        self.move(1)

    def older(self):
        self.move(-1)

    def move(self, step: int) -> None:
        new_index = self.index + step
        if 0 <= new_index < len(self.traces):
            self.index = new_index
            self.show_current()
        else:
            rich.print("[dim]No more traces in that direction.[/]")

    def copy_trace_file_path(self):
        trace = self.current_trace()
        if not trace:
            rich.print("[dim]No trace to copy.[/]")
            return
        self.copy(trace.resolve())

    def copy_take_command(self):
        trace = self.current_trace()
        if not trace:
            rich.print("[dim]No trace to copy.[/]")
            return

        result = subprocess.run(
            ["fish", "-i", "-c", f"_rag_next_share_directory {self.type}"],
            check=False,
            capture_output=True,
            text=True,
        )
        next_share_dir = result.stdout.strip()
        command = f"take {next_share_dir} {trace.resolve()}"
        self.copy(command)

    def copy(self, what):
        try:
            import subprocess, sys
            cmd = "pbcopy" if sys.platform == "darwin" else "xclip -selection clipboard"
            subprocess.run(
                cmd,
                input=str(what),
                text=True,
                shell=True,
                check=False,
            )
            print(f"Copied {what}")
        except Exception:
            print(f"Path: {what}")

    def show_chat(self):
        trace = self.current_trace()
        if trace:
            launch_chat_viewer(trace)
        else:
            print("No trace to display.")

    def on_char(self, char):
        if char == b'h':
            self.print_help()
        elif char == b'c':
            self.copy_trace_file_path()
        elif char == b't':
            self.copy_take_command()
        elif char == b'\n':
            self.show_chat()
        elif char == b'q':
            print("Exiting.")
            sys.exit()
        else:
            rich.print(f"[dim]no handler for {char=}[/]")

    def on_csi(self, sequence):
        UP_ARROW = b'\x1b[A'
        DOWN_ARROW = b'\x1b[B'
        RIGHT_ARROW = b'\x1b[C'
        LEFT_ARROW = b'\x1b[D'

        if sequence == DOWN_ARROW:
            pass
        elif sequence == UP_ARROW:
            pass
        elif sequence == LEFT_ARROW:
            self.older()
        elif sequence == RIGHT_ARROW:
            self.newer()

async def input_loop(browser: TraceBrowser):
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
                            # Read final character of the CSI xterm sequence
                            final = await reader.readexactly(1)
                            sequence += final
                    except Exception as e:
                        rich.print(f"[red]Failed waiting for CSI sequence, skipping sequence: {e}")
                        return

                    browser.on_csi(sequence)

                await read_escape_sequence()
                continue

            browser.on_char(char)

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
    browser = TraceBrowser(args.type)
    asyncio.run(input_loop(browser))

if __name__ == "__main__":
    main()
