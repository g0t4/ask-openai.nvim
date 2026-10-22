"""Read-only NDJSON subscriptions to Neovim's per-process Unix sockets.

Frames replace a message suffix. Each connection starts with a full snapshot,
so neither lost tokens nor reconnects require replaying an event log.
"""
from __future__ import annotations

import asyncio
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Awaitable, Callable

MAX_FRAME_BYTES = 64 * 1024 * 1024


@dataclass
class StreamSnapshot:
    path: Path
    messages: list[dict]
    model_name: str | None
    status: str
    updated_at: float


class StreamState:
    def __init__(self) -> None:
        self.snapshot: StreamSnapshot | None = None
        self.sequence = -1

    def apply(self, event: dict) -> StreamSnapshot:
        if event.get("version") != 1 or event.get("type") != "snapshot":
            raise ValueError("unsupported live trace protocol")
        path = Path(event["trace_path"]).expanduser().resolve()
        prefix = event["replace_from"]
        sequence = event["sequence"]
        messages = event["messages"]
        if (type(prefix) is not int or prefix < 0 or type(sequence) is not int
                or not isinstance(messages, list)
                or not all(isinstance(message, dict) and isinstance(message.get("role"), str) for message in messages)):
            raise ValueError("invalid live trace snapshot")
        if sequence < self.sequence:
            raise ValueError("out-of-order live trace snapshot")
        previous = self.snapshot
        if prefix and (previous is None or previous.path != path or prefix > len(previous.messages)):
            raise ValueError("live trace suffix requires a full snapshot")
        history = previous.messages[:prefix] if previous and prefix else []
        self.snapshot = StreamSnapshot(path, history + messages, event.get("model_name"),
                                       event.get("status", "streaming"), float(event["updated_at"]))
        self.sequence = sequence
        return self.snapshot


class TraceSocketSubscriber:
    """Discover all local publishers; isolate broken/stale sockets and reconnect.

    The callback only stores the newest snapshot; rendering is independently
    throttled by the TUI. Network reads never wait for a terminal redraw.
    """
    def __init__(self, directory: Path, on_snapshot: Callable[[Path, StreamSnapshot], None],
                 on_disconnect: Callable[[Path], None], retry_interval: float = 0.5) -> None:
        self.directory = directory
        self.on_snapshot = on_snapshot
        self.on_disconnect = on_disconnect
        self.retry_interval = retry_interval
        self.connections: dict[Path, asyncio.Task] = {}

    async def _subscribe(self, path: Path) -> None:
        writer = None
        try:
            reader, writer = await asyncio.open_unix_connection(path, limit=MAX_FRAME_BYTES)
            state = StreamState()
            while line := await reader.readline():
                event = json.loads(line)
                if not isinstance(event, dict):
                    raise ValueError("expected a live trace object")
                self.on_snapshot(path, state.apply(event))
        except (OSError, ValueError, KeyError, TypeError, OverflowError):
            # A fresh connection gets a full snapshot, including after backpressure.
            pass
        finally:
            if writer:
                writer.close()
                try:
                    await writer.wait_closed()
                except OSError:
                    pass
            self.on_disconnect(path)

    async def run(self) -> None:
        try:
            while True:
                for path, task in list(self.connections.items()):
                    if task.done():
                        task.result()
                        del self.connections[path]
                try:
                    paths = list(self.directory.glob("live-*.sock"))
                except OSError:
                    paths = []
                for path in paths:
                    try:
                        if path not in self.connections and path.is_socket():
                            self.connections[path] = asyncio.create_task(self._subscribe(path))
                    except OSError:
                        continue
                await asyncio.sleep(self.retry_interval)
        finally:
            tasks = list(self.connections.values())
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
            self.connections.clear()
