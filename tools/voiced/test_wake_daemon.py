"""Tests for the wake-word hands-free PTT flow in the daemon."""

from __future__ import annotations

import asyncio
import json

import numpy as np
import pytest

from tools.voiced.config import socket_path
from tools.voiced.daemon import VoicedDaemon


class FakeTranscriber:
    """Duck-typed stand-in that returns a scripted sequence of texts."""

    def __init__(self, texts: list[str] | None = None) -> None:
        self.texts = texts or ["hello world"]
        self._i = 0
        self.calls = 0

    def transcribe(self, audio: np.ndarray) -> str:
        self.calls += 1
        t = self.texts[self._i % len(self.texts)]
        self._i += 1
        return t


class FakeMic:
    """Duck-typed stand-in that serves a fixed buffer of silence."""

    def __init__(self) -> None:
        self.capture_enabled = False
        self._audio = self._silence()

    def start(self) -> None:
        pass

    def stop(self) -> None:
        pass

    def enable_capture(self, enabled: bool) -> None:
        self.capture_enabled = enabled
        if enabled:
            self.clear()

    def snapshot(self, max_samples: int | None = None) -> np.ndarray:
        data = self._audio
        if max_samples is not None and len(data) > max_samples:
            data = data[-max_samples:]
        return data

    def take(self) -> np.ndarray:
        data = self._audio
        self._audio = self._silence()
        return data

    def clear(self) -> None:
        self._audio = self._silence()

    @staticmethod
    def _silence() -> np.ndarray:
        return np.zeros(16000, dtype=np.float32)


async def _read_until(
    reader: asyncio.StreamReader, predicate, timeout: float = 5.0
) -> dict:
    async def _pump():
        while True:
            line = await reader.readline()
            if not line:
                raise asyncio.TimeoutError("stream closed")
            event = json.loads(line.decode("utf-8"))
            if predicate(event):
                return event

    return await asyncio.wait_for(_pump(), timeout=timeout)


@pytest.mark.asyncio
async def test_wake_word_starts_listening():
    # Sequence: wake phrase, then a real utterance, then stop phrase.
    transcriber = FakeTranscriber(
        texts=["clanker clanker", "hello world", "over"]
    )
    daemon = VoicedDaemon(
        model_path="unused",
        step_ms=50,
        max_length_ms=1000,
        mic=FakeMic(),
        transcriber=transcriber,
        wake_words=True,
    )
    await daemon.start_server()
    try:
        reader, writer = await asyncio.open_unix_connection(str(socket_path()))

        # Wake word should drive the daemon into "listening" state.
        await _read_until(reader, lambda e: e.get("state") == "listening")
        # A live transcription should follow.
        await _read_until(
            reader, lambda e: e["type"] == "transcription" and not e["final"]
        )

        writer.close()
        await writer.wait_closed()
    finally:
        await daemon._shutdown()
