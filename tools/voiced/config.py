"""Central configuration / path helpers for the voiced daemon."""

from __future__ import annotations

import os
from pathlib import Path

APP_NAME = "ask-openai"

# whisper.cpp sample rate (mono, 16-bit PCM)
SAMPLE_RATE = 16000


def state_dir() -> Path:
    """Return the per-user state directory for ask-openai."""
    xdg_state_home = os.environ.get("XDG_STATE_HOME")
    if xdg_state_home:
        return Path(xdg_state_home) / APP_NAME
    return Path.home() / ".local" / "state" / APP_NAME


def socket_path() -> Path:
    """Return the Unix domain socket path used for IPC."""
    return state_dir() / "voiced.sock"


def log_path() -> Path:
    """Return the path transcriptions/daemon logs are appended to."""
    return state_dir() / "voiced.log"


DEFAULT_MODEL_PATH = str(
    Path.home()
    / "Library"
    / "Application Support"
    / "pywhispercpp"
    / "models"
    / "ggml-large-v3-turbo.bin"
)

