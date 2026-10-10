"""Microphone capture using sounddevice, exposing a thread-safe buffer."""

from __future__ import annotations

import threading
from typing import Optional

import numpy as np
import sounddevice as sd

from tools.voiced.config import SAMPLE_RATE


class Microphone:
    """Captures mono float32 PCM at SAMPLE_RATE into an in-memory buffer.

    The stream stays open so we can react to push-to-talk quickly. Samples
    are only accumulated while ``capture_enabled`` is True, which keeps CPU
    low when idle.
    """

    def __init__(self, sample_rate: int = SAMPLE_RATE, device: Optional[int] = None) -> None:
        self._sample_rate = sample_rate
        self._device = device
        self._stream: Optional[sd.InputStream] = None
        self._lock = threading.Lock()
        self._buffer = np.zeros((0,), dtype=np.float32)
        self._capture_enabled = False

    def _audio_callback(self, indata, frames, time_info, status) -> None:
        if not self._capture_enabled:
            return
        with self._lock:
            self._buffer = np.concatenate((self._buffer, indata[:, 0]))

    def start(self) -> None:
        """Open the mic input stream (does not begin capturing yet)."""
        if self._stream is not None:
            return
        self._stream = sd.InputStream(
            samplerate=self._sample_rate,
            channels=1,
            dtype="float32",
            callback=self._audio_callback,
            device=self._device,
        )
        self._stream.start()

    def stop(self) -> None:
        """Close the mic input stream and clear any buffered audio."""
        if self._stream is not None:
            self._stream.stop()
            self._stream.close()
            self._stream = None
        with self._lock:
            self._buffer = np.zeros((0,), dtype=np.float32)
        self._capture_enabled = False

    def enable_capture(self, enabled: bool) -> None:
        """Begin/stop accumulating samples into the buffer."""
        self._capture_enabled = enabled
        if enabled:
            self.clear()

    def snapshot(self, max_samples: Optional[int] = None) -> np.ndarray:
        """Return a copy of everything captured so far (optionally truncated)."""
        with self._lock:
            data = self._buffer.copy()
        if max_samples is not None and len(data) > max_samples:
            data = data[-max_samples:]
        return data

    def take(self) -> np.ndarray:
        """Return and clear everything captured so far."""
        with self._lock:
            data = self._buffer
            self._buffer = np.zeros((0,), dtype=np.float32)
        return data

    def clear(self) -> None:
        """Drop all buffered audio."""
        with self._lock:
            self._buffer = np.zeros((0,), dtype=np.float32)

    def sample_count(self) -> int:
        with self._lock:
            return len(self._buffer)

