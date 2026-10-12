"""Central configuration / path helpers for the clankerd daemon."""

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
    return state_dir() / "clankerd.sock"


def voiced_socket_path() -> Path:
    """Return the voiced daemon's Unix domain socket path."""
    return state_dir() / "voiced.sock"


def log_path() -> Path:
    """Return the path clankerd logs are appended to."""
    return state_dir() / "clankerd.log"


def traces_dir() -> Path:
    """Return the directory where clankerd trace files are written."""
    return state_dir() / "clankerd-traces"
