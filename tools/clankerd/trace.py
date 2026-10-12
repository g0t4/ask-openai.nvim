"""Trace writer for clankerd: appends JSON events per line to a trace file."""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any
from uuid import uuid4

from tools.clankerd.config import traces_dir
from tools.clankerd.logger import get_logger

logger = get_logger(__name__)


class TraceWriter:
    """Writes a newline-delimited JSON trace for one clankerd session.

    Each trace is a single file under ``traces_dir()`` named
    ``<timestamp>-<trace_id>.json``. Events are appended immediately so the
    trace is inspectable while the daemon is still running.
    """

    def __init__(self, trace_id: str | None = None) -> None:
        self.trace_id = trace_id or uuid4().hex[:12]
        self.path: Path = traces_dir() / f"{time.time():.6f}-{self.trace_id}.json"
        traces_dir().mkdir(parents=True, exist_ok=True)
        self._write({"type": "trace_started", "trace_id": self.trace_id})

    def event(self, event_type: str, **fields: Any) -> None:
        """Append a trace event."""
        event: dict[str, Any] = {
            "type": event_type,
            "timestamp": time.time(),
            "trace_id": self.trace_id,
        }
        event.update(fields)
        self._write(event)

    def _write(self, event: dict[str, Any]) -> None:
        try:
            with open(self.path, "a") as f:
                f.write(json.dumps(event, default=str) + "\n")
        except OSError as error:
            logger.warning("trace write failed: %s", error)
