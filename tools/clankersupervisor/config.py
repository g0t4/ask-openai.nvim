"""Central configuration / path helpers for the clankersupervisor daemon."""

from __future__ import annotations

import os
from pathlib import Path

APP_NAME = "ask-openai"


def state_dir() -> Path:
    """Return the per-user state directory for ask-openai."""
    xdg_state_home = os.environ.get("XDG_STATE_HOME")
    if xdg_state_home:
        return Path(xdg_state_home) / APP_NAME
    return Path.home() / ".local" / "state" / APP_NAME


def socket_path() -> Path:
    """Return the Unix domain socket path used for IPC."""
    return state_dir() / "clankersupervisor.sock"


def log_path() -> Path:
    """Return the path supervisor logs are appended to."""
    return state_dir() / "clankersupervisor.log"


def pid_path() -> Path:
    """Return the path to the supervisor's PID file."""
    return state_dir() / "clankersupervisor.pid"

