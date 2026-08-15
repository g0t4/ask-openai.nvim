"""Interactive Textual-based viewer for chat traces.

A remake of the ``view_trace`` CLI using `textual <https://textual.textualize.io/>`_
so a trace can be explored interactively instead of dumped all at once:

* ``a`` toggles between the condensed view and the expanded ``--all`` view
  (showing the extra context that is normally excluded).
* ``q`` quits.

It reuses *all* of the rendering logic from ``tools.chat_viewer.__main__`` by
pointing the module's rich ``Console`` at a ``RichLog`` widget, so the
interactive view shows exactly the same content as the plain CLI dump.
"""

from __future__ import annotations

import argparse
import argcomplete
import io
import sys
from pathlib import Path

from rich.console import Console
from rich.text import Text
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.widgets import Footer, Header, RichLog

from tools.chat_viewer import __main__ as viewer


class RichLogFile(io.TextIOBase):
    """File-like object routing rich Console output into a ``RichLog``.

    The rich ``Console`` renders its output as ANSI text and writes it through
    ``write()``. We buffer by line (so escape sequences never get split) and
    forward each completed line to the widget as a ``Text`` renderable.
    """

    def __init__(self, log: RichLog) -> None:
        self._log = log
        self._buffer = ""

    def write(self, s: str) -> int:
        self._buffer += s
        while "\n" in self._buffer:
            line, self._buffer = self._buffer.split("\n", 1)
            self._log.write(Text.from_ansi(line))
        return len(s)

    def flush(self) -> None:
        if self._buffer:
            self._log.write(Text.from_ansi(self._buffer))
            self._buffer = ""


class TraceViewerApp(App):
    """Textual app for interactively browsing a chat trace."""

    TITLE = "Ask Trace Viewer"
    SUB_TITLE = "a: toggle all · q: quit"

    BINDINGS = [
        Binding("a", "toggle_all", "Toggle all content", show=True),
        Binding("q", "quit", "Quit", show=False),
    ]

    CSS = """
    RichLog {
        border: round $accent;
        padding: 0 1;
    }
    """

    def __init__(
        self,
        messages: list[dict],
        model_name: str | None = None,
        timings=None,
    ) -> None:
        super().__init__()
        self._messages = messages
        self._model_name = model_name
        self._timings = timings

    def compose(self) -> ComposeResult:
        yield Header()
        yield RichLog(highlight=True, markup=False, wrap=True, id="trace-log")
        yield Footer()

    def _render(self) -> None:
        log = self.query_one(RichLog)
        log.clear()
        # Generous width so rich does not hard-wrap; RichLog wraps to its own width.
        console = Console(
            file=RichLogFile(log),
            soft_wrap=True,
            color_system="truecolor",
            width=400,
        )
        viewer.render_trace_to_console(
            console, self._messages, self._model_name, self._timings
        )

    def on_mount(self) -> None:
        viewer.SHOW_ALL = False
        self._render()

    def action_toggle_all(self) -> None:
        viewer.SHOW_ALL = not viewer.SHOW_ALL
        self._render()


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description="Interactive textual trace viewer (a: toggle all, q: quit)"
    )
    parser.add_argument(
        "trace_file",
        nargs="?",
        default=None,
        help="path to trace file (or stdin if omitted)",
    )
    argcomplete.autocomplete(parser)
    args = parser.parse_args(argv)

    viewer.load_preapproved_files()

    if args.trace_file:
        messages, model_name, timings = viewer.load_trace_messages_from_path(
            Path(args.trace_file)
        )
    elif not sys.stdin.isatty():
        messages, model_name, timings = viewer.load_trace_messages_from_stream(
            sys.stdin
        )
    else:
        parser.print_help()
        return

    TraceViewerApp(messages, model_name, timings).run()


if __name__ == "__main__":
    main()
