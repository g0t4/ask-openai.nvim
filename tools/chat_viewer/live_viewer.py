"""Follow the most recently saved agent trace using the shared Python renderer.

Run ``python -m tools.chat_viewer.live_viewer [directory]`` or ``view_trace --watch``.
Only changed message suffixes are replaced; unchanged widgets retain their state.
"""
from __future__ import annotations

import argparse
import asyncio
import io
import json
import os
from dataclasses import dataclass
from pathlib import Path

from rich.console import Console
from rich.text import Text
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import VerticalScroll
from textual.widgets import Footer, Header, Static

from tools.chat_viewer import __main__ as viewer
from tools.chat_viewer.terminal_app import TerminalSizedApp


def default_trace_directory() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "nvim/ask-openai/agents"


@dataclass
class TraceSnapshot:
    path: Path
    messages: list[dict]
    model_name: str | None


class TraceDirectoryWatcher:
    """Poll file metadata, loading JSON only when the newest file changes.

    Remember a save only after a stable, valid read. Truncated/in-progress saves
    are retried without discarding the displayed snapshot.
    """
    def __init__(self, directory: Path) -> None:
        self.directory = directory.expanduser()
        self._loaded_signature = None
        self.error: str | None = None

    def poll(self) -> TraceSnapshot | None:
        candidates = []
        try:
            for path in self.directory.glob("*-trace.json"):
                try:
                    stat = path.stat()
                    if path.is_file():
                        candidates.append((stat.st_mtime_ns, path.name, path, stat))
                except OSError:
                    continue
        except OSError as error:
            self.error = str(error)
            return None
        if not candidates:
            self.error = f"Waiting for traces in {self.directory}"
            return None
        _, _, path, before = max(candidates, key=lambda candidate: candidate[:2])
        signature = (path, before.st_mtime_ns, before.st_size, before.st_ino)
        if signature == self._loaded_signature:
            self.error = None
            return None
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            after = path.stat()
            if (before.st_mtime_ns, before.st_size, before.st_ino) != (after.st_mtime_ns, after.st_size, after.st_ino):
                self.error = f"Waiting for {path.name} to finish saving"
                return None
            messages = data.get("request_body", data).get("messages")
            if not isinstance(messages, list) or not all(isinstance(message, dict) and "role" in message for message in messages):
                raise ValueError("expected an array of trace messages")
            if isinstance(data.get("response_message"), dict):
                messages = [*messages, data["response_message"]]
            model_name = (data.get("last_sse") or {}).get("model")
        except (OSError, ValueError, AttributeError, TypeError) as error:
            self.error = f"Waiting for a complete save of {path.name}: {error}"
            return None
        self._loaded_signature = signature
        self.error = None
        return TraceSnapshot(path, messages, model_name)


def unchanged_prefix(previous: list[dict], current: list[dict]) -> int:
    for index, (old, new) in enumerate(zip(previous, current)):
        if old != new:
            return index
    return min(len(previous), len(current))


class TraceViewport(VerticalScroll):
    def on_resize(self) -> None:
        # Listen to the viewport itself, after its new layout dimensions exist.
        self.call_after_refresh(self.app._reflow_after_resize)


class LiveTraceViewerApp(TerminalSizedApp):
    TITLE = "Live Agent Traces"
    BINDINGS = [
        Binding("f", "toggle_follow", "Follow latest"),
        Binding("a", "toggle_all", "Toggle all content"),
        Binding("r", "toggle_reasoning_style", "Reasoning style"),
        Binding("q", "quit", "Quit"),
    ]
    CSS = """
    Screen { layout: vertical; }
    #transcript {
        width: 100%; height: 1fr;
        border: none; background: transparent;
        scrollbar-gutter: stable;
    }
    .trace-message { width: 100%; height: auto; background: transparent; }
    """

    def __init__(self, directory: Path, poll_interval: float = 0.25) -> None:
        super().__init__()
        self.watcher = TraceDirectoryWatcher(directory)
        self.poll_interval = poll_interval
        self.snapshot: TraceSnapshot | None = None
        self.follow_latest = True
        self._polling = False
        self._live_view_mounted = False
        self._render_lock = asyncio.Lock()
        self._rendered_viewport_width: int | None = None

    def get_css_variables(self) -> dict[str, str]:
        variables = super().get_css_variables()
        for name in ("background", "surface", "panel"):
            variables[name] = "transparent"
        return variables

    def compose(self) -> ComposeResult:
        yield Header()
        yield TraceViewport(Static("Waiting for an agent trace…", id="waiting"), id="transcript")
        yield Footer()

    async def on_mount(self) -> None:
        self._live_view_mounted = True
        self._previous_render_options = (viewer.SHOW_ALL, viewer.STYLE_REASONING, viewer.SHOW_STATS)
        viewer.SHOW_STATS = True
        self.query_one("#transcript").focus()
        self.set_interval(self.poll_interval, self.poll_directory)
        await self.poll_directory()

    def on_unmount(self) -> None:
        viewer.SHOW_ALL, viewer.STYLE_REASONING, viewer.SHOW_STATS = self._previous_render_options

    def _update_title(self) -> None:
        state = "following" if self.follow_latest else "scroll paused · f to follow"
        self.title = f"Live Agent Traces · {self.size.width}×{self.size.height}"
        if self.watcher.error:
            self.sub_title = self.watcher.error
        elif self.snapshot:
            self.sub_title = f"{self.snapshot.path.name} · {self.snapshot.model_name or 'unknown model'} · {state}"

    async def poll_directory(self) -> None:
        if self._polling:
            return
        self._polling = True
        try:
            snapshot = await asyncio.to_thread(self.watcher.poll)
            if snapshot is not None:
                await self.update_trace(snapshot)
            self._update_title()
        finally:
            self._polling = False

    def _message_widget(self, snapshot: TraceSnapshot, index: int) -> Static:
        output = io.StringIO()
        transcript = self.query_one("#transcript", VerticalScroll)
        self._rendered_viewport_width = max(1, transcript.scrollable_content_region.width)
        console = Console(file=output, width=self._rendered_viewport_width,
                          color_system="truecolor", force_terminal=True)
        try:
            viewer.render_messages_to_console(console, [snapshot.messages[index]], start_index=index + 1,
                                              context_messages=snapshot.messages, full_width=True)
        except Exception as error:
            console.print(f"Unable to render message #{index + 1}: {error}", markup=False, style="red")
        widget = Static(Text.from_ansi(output.getvalue()), id=f"message-{index}", classes="trace-message")
        widget.display = bool(output.getvalue())
        return widget

    async def update_trace(self, snapshot: TraceSnapshot, *, full: bool = False) -> None:
        async with self._render_lock:
            if full and self.snapshot:
                snapshot = self.snapshot
            await self._update_trace(snapshot, full=full)

    async def _update_trace(self, snapshot: TraceSnapshot, *, full: bool) -> None:
        transcript = self.query_one("#transcript", VerticalScroll)
        previous = self.snapshot
        same_trace = previous is not None and previous.path == snapshot.path
        prefix = unchanged_prefix(previous.messages, snapshot.messages) if same_trace and not full else 0
        scroll_y = transcript.scroll_y
        # Build the replacement first: a render error must not erase the old view.
        widgets = [self._message_widget(snapshot, index) for index in range(prefix, len(snapshot.messages))]
        for child in list(transcript.children)[prefix:]:
            await child.remove()
        if widgets:
            await transcript.mount(*widgets)
        self.snapshot = snapshot
        self._update_title()
        if self.follow_latest:
            self.call_after_refresh(transcript.scroll_end, animate=False, x_axis=False)
        else:
            self.call_after_refresh(transcript.scroll_to, y=scroll_y, animate=False)

    async def _reflow_after_resize(self) -> None:
        if self._live_view_mounted and self.snapshot:
            width = max(1, self.query_one("#transcript", VerticalScroll).scrollable_content_region.width)
            if width != self._rendered_viewport_width:
                await self.update_trace(self.snapshot, full=True)

    async def action_toggle_all(self) -> None:
        viewer.SHOW_ALL = not viewer.SHOW_ALL
        if self.snapshot:
            await self.update_trace(self.snapshot, full=True)

    async def action_toggle_reasoning_style(self) -> None:
        viewer.STYLE_REASONING = not viewer.STYLE_REASONING
        if self.snapshot:
            await self.update_trace(self.snapshot, full=True)

    def action_toggle_follow(self) -> None:
        self.follow_latest = not self.follow_latest
        self._update_title()
        if self.follow_latest:
            self.query_one("#transcript", VerticalScroll).scroll_end(animate=False, x_axis=False)


def run_live(directory: Path, *, show_all: bool = False, style_reasoning: bool = True) -> None:
    viewer.SHOW_ALL = show_all
    viewer.STYLE_REASONING = style_reasoning
    viewer.load_preapproved_files()
    LiveTraceViewerApp(directory).run()


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", nargs="?", type=Path, default=default_trace_directory())
    args = parser.parse_args(argv)
    run_live(args.directory)


if __name__ == "__main__":
    main()
