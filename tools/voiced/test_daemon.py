"""Pytest tests for the voiced daemon's socket IPC protocol."""

from __future__ import annotations

import asyncio
import json
import tempfile
from pathlib import Path

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
        live = await _read_until(reader, lambda e: e["type"] == "transcription")
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


@pytest.fixture(autouse=True)
def isolated_socket(monkeypatch):
    """Never unlink the user's running voiced socket during tests."""
    with tempfile.TemporaryDirectory(dir="/tmp", prefix="voiced-test-") as directory:
        path = Path(directory) / "v.sock"
        monkeypatch.setattr("tools.voiced.daemon.socket_path", lambda: path)
        monkeypatch.setitem(globals(), "socket_path", lambda: path)
        yield


@pytest.mark.asyncio
async def test_private_dictation_isolation_busy_and_disconnect():
    daemon = VoicedDaemon(
        model_path="unused", step_ms=10, mic=FakeMic(), transcriber=FakeTranscriber()
    )
    await daemon.start_server()
    clients = [await asyncio.open_unix_connection(str(socket_path())) for _ in range(3)]
    owner, observer, other = clients

    async def command(client, kind):
        client[1].write((json.dumps({"type": kind}) + "\n").encode())
        await client[1].drain()

    try:
        await command(owner, "hello")
        assert (await _read_until(owner[0], lambda e: e["type"] == "hello"))[
            "private_dictation"
        ] == 1
        await command(owner, "dictation_start")
        await _read_until(owner[0], lambda e: e.get("state") == "listening")
        await command(other, "dictation_start")
        assert (
            "busy"
            in (await _read_until(other[0], lambda e: e["type"] == "error"))["message"]
        )
        await command(observer, "stop")
        await daemon.stop_listening()  # hardware PTT release must not end private input
        assert daemon._listening
        await command(owner, "dictation_stop")
        final = await _read_until(owner[0], lambda e: e.get("final"))
        assert final["text"] == "hello world"
        await _read_until(owner[0], lambda e: e.get("state") == "idle")
        assert daemon._dictation_owner is None
        # Ordering barrier: global ping follows finalization, with no private events before it.
        for client in (observer, other):
            await command(client, "ping")
            assert json.loads(await asyncio.wait_for(client[0].readline(), 1)) == {
                "type": "pong"
            }
        await command(owner, "dictation_start")
        await _read_until(owner[0], lambda e: e.get("state") == "listening")
        owner[1].close()
        await owner[1].wait_closed()
        for _ in range(100):
            if daemon._dictation_owner is None:
                break
            await asyncio.sleep(0.01)
        assert daemon._dictation_owner is None and not daemon._listening
        await command(observer, "start")
        await _read_until(observer[0], lambda e: e.get("state") == "listening")
        await command(other, "dictation_start")
        assert (
            "busy"
            in (await _read_until(other[0], lambda e: e["type"] == "error"))["message"]
        )
        await command(observer, "stop")
        await _read_until(observer[0], lambda e: e.get("state") == "idle")
    finally:
        for _, writer in clients:
            writer.close()
            await writer.wait_closed()
        await daemon._shutdown()


@pytest.mark.asyncio
async def test_private_transcription_failure_releases_microphone():
    class Broken:
        def transcribe(self, audio):
            raise RuntimeError("recognizer unavailable")

    daemon = VoicedDaemon(
        model_path="unused", step_ms=1000, mic=FakeMic(), transcriber=Broken()
    )
    await daemon.start_server()
    reader, writer = await asyncio.open_unix_connection(str(socket_path()))
    try:
        writer.write(b'{"type":"dictation_start"}\n{"type":"dictation_stop"}\n')
        await writer.drain()
        error = await _read_until(reader, lambda e: e["type"] == "error")
        assert error["message"] == "recognizer unavailable"
        await _read_until(reader, lambda e: e.get("state") == "idle")
        assert daemon._dictation_owner is None
        assert not daemon._mic.capture_enabled
        assert not daemon._finishing
    finally:
        writer.close()
        await writer.wait_closed()
        await daemon._shutdown()
