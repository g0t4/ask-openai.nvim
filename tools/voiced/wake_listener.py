"""Continuous wake-word listening for the voiced daemon.

While the PTT is not pressed, this module runs a background loop that keeps
capturing mic audio (in a small rolling buffer) and periodically transcribes
it to look for a wake phrase. When a wake phrase is heard it triggers
``on_wake``; a stop phrase triggers ``on_stop``.
"""

from __future__ import annotations

import asyncio
from typing import Callable, Optional

import numpy as np

from tools.voiced.config import SAMPLE_RATE
from tools.voiced.mic import Microphone
from tools.voiced.transcriber import Transcriber
from tools.voiced.voiced_logger import get_logger
from tools.voiced.wake import detect

logger = get_logger(__name__)


class WakeListener:
    """Watches a rolling mic buffer for wake/stop phrases while idle."""

    def __init__(
        self,
        mic: Microphone,
        transcriber: Transcriber,
        on_wake: Callable[[], None],
        on_stop: Callable[[], None],
        *,
        step_ms: int = 1500,
        max_length_ms: int = 8000,
    ) -> None:
        self._mic = mic
        self._transcriber = transcriber
        self._on_wake = on_wake
        self._on_stop = on_stop
        self._step_seconds = step_ms / 1000.0
        self._max_samples = int(max_length_ms / 1000.0 * SAMPLE_RATE)
        self._task: Optional[asyncio.Task] = None
        self._running = False
        self._last_wake_text = ""

    async def start(self) -> None:
        """Begin continuous wake listening (idempotent)."""
        if self._running:
            return
        self._running = True
        self._mic.enable_capture(True)
        self._task = asyncio.create_task(self._loop())
        logger.info("wake-word listener started")

    async def stop(self) -> None:
        """Stop wake listening and clear the buffer."""
        if not self._running:
            return
        self._running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
            self._task = None
        self._mic.clear()
        logger.info("wake-word listener stopped")

    async def _loop(self) -> None:
        while self._running:
            await asyncio.sleep(self._step_seconds)
            if not self._running:
                break
            audio = self._mic.snapshot(max_samples=self._max_samples)
            if audio.size == 0:
                continue
            loop = asyncio.get_running_loop()
            text = await loop.run_in_executor(
                None, self._transcriber.transcribe, audio
            )
            if not text:
                continue
            action = detect(text)
            logger.info("wake listener transcript: %r -> %s", text, action)
            if action == "wake":
                self._last_wake_text = text
                self._on_wake()
            elif action == "stop":
                self._on_stop()

    @property
    def last_wake_text(self) -> str:
        return self._last_wake_text
