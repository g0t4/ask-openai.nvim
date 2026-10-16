"""Central configuration / path helpers for the voiced daemon."""

from __future__ import annotations

import os
from pathlib import Path

APP_NAME = "ask-openai"

# whisper.cpp sample rate (mono, 16-bit PCM)
SAMPLE_RATE = 16000

# --------------------------------------------------------------------- wake word
# Default wake phrase (spoken hands-free). Matching is case-insensitive and
# punctuation-insensitive, so "Hey Clinker", "hey clinker", and "Hey, Clinker"
# all trigger.
DEFAULT_WAKE_PHRASE = "hey clinker"

# How often (seconds) the wake-word detector transcribes the rolling audio
# window while idle. Larger = lower CPU, slightly higher latency.
DEFAULT_WAKE_CHECK_INTERVAL_SECONDS = 1.0

# Length of audio (seconds) fed to whisper for each wake-word check.
DEFAULT_WAKE_WINDOW_SECONDS = 2.0

# Once the wake phrase is detected we start listening; we auto-stop after this
# much continuous silence (seconds) or after ``DEFAULT_WAKE_MAX_LISTEN_SECONDS``.
DEFAULT_WAKE_STOP_SILENCE_SECONDS = 1.5
DEFAULT_WAKE_MAX_LISTEN_SECONDS = 15.0

# RMS (float32) below which audio is treated as silence for auto-stop.
DEFAULT_WAKE_SILENCE_RMS = 0.01


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
