"""The voiced daemon: mic + whisper.cpp streaming + Unix socket IPC."""

from __future__ import annotations

import asyncio
import json
from typing import Optional

import numpy as np

from tools.voiced.config import SAMPLE_RATE, socket_path
from tools.voiced.mic import Microphone
from tools.voiced.ptt import PushToTalk
from tools.voiced.transcriber import Transcriber
from tools.voiced.voiced_logger import get_logger

logger = get_logger(__name__)


class VoicedDaemon:
    """Owns the mic, transcriber, PTT state machine, and socket server."""

    def __init__(
        self,
        model_path: str,
        n_threads: int = 4,
        step_ms: int = 1500,
        max_length_ms: int = 30000,
        device: Optional[int] = None,
        mic: Optional[Microphone] = None,
        transcriber: Optional[Transcriber] = None,
    ) -> None:
        self._mic = mic or Microphone(device=device)
        self._device = device
        self._transcriber = transcriber or Transcriber(model_path, n_threads=n_threads)
        self._step_seconds = step_ms / 1000.0
        self._max_length_samples = int(max_length_ms / 1000.0 * SAMPLE_RATE)

        self._clients: set[asyncio.StreamWriter] = set()
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._listening = False
        self._transcribe_task: Optional[asyncio.Task] = None
        self._server: Optional[asyncio.AbstractServer] = None

        self._ptt = PushToTalk(
            on_press=self._on_ptt_press,
            on_release=self._on_ptt_release,
        )

    async def run(self) -> None:
        """Start mic, PTT listener, and socket server; block forever."""
        self._loop = asyncio.get_running_loop()

        self._mic.start()
        logger.info("mic started (device=%s, %d Hz)", self._device, SAMPLE_RATE)

        self._ptt.start_hardware_listener()

        await self.start_server()

        try:
            await asyncio.Future()  # run forever
        finally:
            await self._shutdown()

    async def start_server(self) -> None:
        """Start the Unix socket server (idempotent)."""
        if self._server is not None:
            return
        socket_path().parent.mkdir(parents=True, exist_ok=True)
        if socket_path().exists():
            socket_path().unlink()
        self._server = await asyncio.start_unix_server(
            self._handle_client,
            path=str(socket_path()),
        )
        logger.info("socket server listening at %s", socket_path())

    # ------------------------------------------------------------------ PTT

    def _on_ptt_press(self) -> None:
        if self._loop:
            asyncio.run_coroutine_threadsafe(self.start_listening(), self._loop)

    def _on_ptt_release(self) -> None:
        if self._loop:
            asyncio.run_coroutine_threadsafe(self.stop_listening(), self._loop)

    async def start_listening(self) -> None:
        if self._listening:
            return
        self._listening = True
        self._mic.enable_capture(True)
        self._transcribe_task = asyncio.create_task(self._transcribe_loop())
        await self._broadcast({"type": "status", "state": "listening"})

    async def stop_listening(self) -> None:
        if not self._listening:
            return
        self._listening = False
        if self._transcribe_task:
            await self._transcribe_task
            self._transcribe_task = None

        # Final transcription of the complete utterance.
        audio = self._mic.take()
        text = await self._run_transcribe(audio)
        if text:
            logger.info("transcription [final]: %s", text)
            await self._broadcast(
                {"type": "transcription", "text": text, "final": True}
            )
        self._mic.enable_capture(False)
        await self._broadcast({"type": "status", "state": "idle"})

    async def _transcribe_loop(self) -> None:
        while self._listening:
            await asyncio.sleep(self._step_seconds)
            if not self._listening:
                break
            audio = self._mic.snapshot(max_samples=self._max_length_samples)
            text = await self._run_transcribe(audio)
            if text:
                logger.info("transcription [live]: %s", text)
                await self._broadcast(
                    {"type": "transcription", "text": text, "final": False}
                )

    async def _run_transcribe(self, audio: np.ndarray) -> str:
        if audio.size == 0:
            return ""
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, self._transcriber.transcribe, audio)

    # ----------------------------------------------------------- socket IPC

    async def _handle_client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        self._clients.add(writer)
        logger.info("client connected (%d total)", len(self._clients))
        try:
            while True:
                line = await reader.readline()
                if not line:
                    break
                await self._handle_command(line.decode("utf-8").strip(), writer)
        except asyncio.CancelledError:
            pass
        finally:
            self._clients.discard(writer)
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass
            logger.info("client disconnected (%d total)", len(self._clients))

    async def _handle_command(self, raw: str, writer: asyncio.StreamWriter) -> None:
        if not raw:
            return
        try:
            command = json.loads(raw)
        except json.JSONDecodeError:
            await self._send(writer, {"type": "error", "message": f"bad json: {raw}"})
            return

        command_type = command.get("type")
        if command_type == "start":
            await self.start_listening()
        elif command_type == "stop":
            await self.stop_listening()
        elif command_type == "press":
            self._ptt.press()
        elif command_type == "release":
            self._ptt.release()
        elif command_type == "ping":
            await self._send(writer, {"type": "pong"})
        elif command_type == "shutdown":
            await self._broadcast({"type": "status", "state": "shutdown"})
            asyncio.get_running_loop().stop()
        else:
            await self._send(
                writer,
                {"type": "error", "message": f"unknown command: {command_type}"},
            )

    async def _send(self, writer: asyncio.StreamWriter, event: dict) -> None:
        data = json.dumps(event) + "\n"
        try:
            writer.write(data.encode("utf-8"))
            await writer.drain()
        except Exception:
            self._clients.discard(writer)

    async def _broadcast(self, event: dict) -> None:
        for writer in list(self._clients):
            await self._send(writer, event)

    async def _shutdown(self) -> None:
        logger.info("shutting down")
        if self._server:
            self._server.close()
            await self._server.wait_closed()
        self._mic.stop()
        if self._transcribe_task and not self._transcribe_task.done():
            self._transcribe_task.cancel()
