"""Pytest tests for the voiced daemon's socket IPC protocol."""

from __future__ import annotations

import asyncio
import json

import numpy as np
import pytest

from tools.voiced.config import socket_path
from tools.voiced.daemon import VoicedDaemon


class FakeTranscriber:
    """Duck-typed stand-in that always returns a fixed string."""

    def transcribe(self, audio: np.ndarray) -> str:
        return "hello world"


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
async def test_ping_pong_and_ptt_flow():
    daemon = VoicedDaemon(
        model_path="unused",
        step_ms=50,
        max_length_ms=1000,
        mic=FakeMic(),
        transcriber=FakeTranscriber(),
    )
    await daemon.start_server()
    try:
        reader, writer = await asyncio.open_unix_connection(str(socket_path()))

        # ping -> pong
        writer.write(b'{"type":"ping"}\n')
        await writer.drain()
        pong = await _read_until(reader, lambda e: e["type"] == "pong")
        assert pong == {"type": "pong"}

        # start -> status listening, then a live transcription
        writer.write(b'{"type":"start"}\n')
        await writer.drain()
        await _read_until(reader, lambda e: e.get("state") == "listening")
        live = await _read_until(
            reader, lambda e: e["type"] == "transcription"
        )
        assert live["text"] == "hello world"
        assert live["final"] is False

        # stop -> final transcription + status idle
        writer.write(b'{"type":"stop"}\n')
        await writer.drain()
        final = await _read_until(
            reader, lambda e: e["type"] == "transcription" and e["final"]
        )
        assert final["text"] == "hello world"
        await _read_until(reader, lambda e: e.get("state") == "idle")

        writer.close()
        await writer.wait_closed()
    finally:
        await daemon._shutdown()
